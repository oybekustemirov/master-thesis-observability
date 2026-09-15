package itpu.uz.masterthesisobservability.outbox;

import io.micrometer.core.instrument.MeterRegistry;
import itpu.uz.masterthesisobservability.config.ObservabilityProperties;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import static java.nio.charset.StandardCharsets.UTF_8;

/**
 * Polling relay for variant B3. In {@code HYBRID} mode Debezium reads the same outbox rows
 * from the redo log instead, so this component is not created there either.
 *
 * <p>An earlier version of this comment claimed the Debezium relay "cuts end-to-end latency".
 * Measurement refutes it. At a 50 TPS profile this relay delivered a median of 125 ms while
 * the hybrid measured 3 360 ms: replacing the poll does remove the polling query from the
 * database, but Debezium's own LogMiner cycle is a slower poll than this one. What the hybrid
 * buys is coverage of writers that never call this application and the removal of polling load
 * from the OLTP instance — not latency.
 *
 * <p>The bean is conditional rather than self-disabling. Returning early inside a
 * {@code @Transactional} scheduled method still opened a database transaction and borrowed a
 * pooled connection five times a second in EVERY mode, including the OFF and BASELINE_GT
 * baselines, charging every measurement for work that only one mode does. Not creating the
 * bean removes the scheduled task altogether.
 */
@Component
@ConditionalOnProperty(name = "observability.mode", havingValue = "WRAPPER_B3")
@RequiredArgsConstructor
@Slf4j
public class OutboxRelay {

    /**
     * Claiming the next batch IN COMMIT ORDER on Oracle is harder than it looks, and getting
     * it wrong silently reorders events without losing any — a defect that no loss metric
     * detects.
     *
     * <p>Three approaches fail:
     * <ul>
     *   <li>{@code WHERE ROWNUM <= n ... ORDER BY ID} — <b>ROWNUM is applied BEFORE ORDER BY</b>,
     *       so this takes an arbitrary n rows and then sorts those. Measured effect: 2.6% of
     *       transactions were delivered out of order, e.g. PROCESSED at offset 13 ahead of
     *       VALIDATED at offset 67, even though the outbox rows themselves were correctly
     *       ordered.</li>
     *   <li>{@code SELECT ... FROM (SELECT ... ORDER BY ID) WHERE ROWNUM <= n FOR UPDATE} —
     *       ORA-02014: cannot select FOR UPDATE from a view.</li>
     *   <li>{@code ORDER BY ID FETCH FIRST n ROWS ONLY FOR UPDATE} — also ORA-02014, because
     *       FETCH FIRST is rewritten as an analytic-function view.</li>
     * </ul>
     *
     * <p>What works is two statements: establish the high-water ID of the ordered first n
     * rows, then lock that range. The second statement has no inline view, so FOR UPDATE
     * SKIP LOCKED is permitted.
     */
    private static final String HIGH_WATER_SQL = """
            SELECT MAX(ID) FROM (
              SELECT ID FROM A1_EVENT_OUTBOX WHERE PUBLISHED_AT IS NULL ORDER BY ID)
             WHERE ROWNUM <= ?
            """;

    /**
     * {@code SKIP LOCKED} lets every application instance relay concurrently without a
     * distributed lock and without duplicating work, which is what makes the relay
     * horizontally scalable and highly available. Global ordering across instances is not
     * preserved; per-aggregate ordering is, because Kafka partitions on AGGREGATE_ID.
     */
    private static final String CLAIM_SQL = """
            SELECT ID, EVENT_ID, AGGREGATE_TYPE, AGGREGATE_ID, EVENT_TYPE, EVENT_SEQ,
                   SCHEMA_VERSION, TRACE_ID, PAYLOAD
              FROM A1_EVENT_OUTBOX
             WHERE PUBLISHED_AT IS NULL
               AND ID <= ?
             ORDER BY ID
               FOR UPDATE SKIP LOCKED
            """;

    private static final String MARK_SQL =
            "UPDATE A1_EVENT_OUTBOX SET PUBLISHED_AT = SYSTIMESTAMP, ATTEMPTS = ATTEMPTS + 1 "
          + "WHERE ID = ?";

    private final JdbcTemplate jdbc;
    private final KafkaTemplate<String, String> kafka;
    private final MeterRegistry meters;
    private final ObservabilityProperties properties;

    @Scheduled(fixedDelayString = "${observability.outbox.poll-interval:200ms}")
    @Transactional
    public void relay() {
        Long highWater = jdbc.queryForObject(HIGH_WATER_SQL, Long.class,
                                             properties.outbox().batchSize());
        if (highWater == null) {
            return;
        }
        var batch = jdbc.query(CLAIM_SQL, OutboxRow.MAPPER, highWater);
        if (batch.isEmpty()) {
            return;
        }
        // Pipeline the whole batch, THEN wait. Sending and blocking one record at a time
        // caps the relay at roughly one record per broker round trip, which at 150 events/s
        // built a multi-second backlog and made the measured end-to-end latency a property
        // of the relay implementation rather than of the outbox pattern. Batching removes
        // that artefact; the producer's own linger/batching then does the real work.
        var inFlight = new java.util.ArrayList<java.util.concurrent.CompletableFuture<?>>(batch.size());
        for (OutboxRow row : batch) {
            inFlight.add(publish(row));
        }
        // A failure here aborts the transaction, so the rows stay unpublished and are
        // retried on the next poll: at-least-once, never at-most-once.
        java.util.concurrent.CompletableFuture
                .allOf(inFlight.toArray(java.util.concurrent.CompletableFuture[]::new))
                .join();

        var ids = batch.stream().map(OutboxRow::id).toList();
        jdbc.batchUpdate(MARK_SQL, ids, ids.size(),
                (ps, id) -> ps.setLong(1, id));

        meters.counter("obsv.outbox.relayed").increment(batch.size());
        log.debug("relayed {} outbox rows", batch.size());
    }

    private java.util.concurrent.CompletableFuture<?> publish(OutboxRow row) {
        // Routed by aggregate type. A1 transitions and credit stage changes are different
        // aggregates with different consumers, and the A1 reconciliation would score a credit
        // event arriving on its topic as a phantom.
        var record = new ProducerRecord<>(
                properties.topicFor(row.aggregateType()), row.aggregateId(), row.payload());
        record.headers().add("eventId", row.eventIdHex().getBytes(UTF_8));
        record.headers().add("eventType", row.eventType().getBytes(UTF_8));
        record.headers().add("eventSeq", String.valueOf(row.eventSeq()).getBytes(UTF_8));
        record.headers().add("schemaVersion", row.schemaVersion().getBytes(UTF_8));
        record.headers().add("sourceSystem", "APP".getBytes(UTF_8));
        if (row.traceId() != null) {
            record.headers().add("traceId", row.traceId().getBytes(UTF_8));
        }
        // Returned unresolved: the caller waits for the whole batch. The row is marked
        // published only after acks=all, so a crash between the ack and the mark redelivers
        // the event — at-least-once, with a duplicate window but no loss window. Consumers
        // deduplicate on EVENT_ID.
        return kafka.send(record);
    }
}

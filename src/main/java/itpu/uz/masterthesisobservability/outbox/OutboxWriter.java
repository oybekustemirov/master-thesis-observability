package itpu.uz.masterthesisobservability.outbox;

import tools.jackson.databind.ObjectMapper;
import itpu.uz.masterthesisobservability.metrics.TraceContext;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.nio.ByteBuffer;
import java.util.UUID;

/**
 * Writes one outbox row through the caller's transaction, so the event and the business state
 * change share a single commit. This is what makes variant B3 structurally incapable of losing
 * an event: there is no window in which the business fact is durable and the event is not.
 */
@Component
@RequiredArgsConstructor
public class OutboxWriter {

    private static final String INSERT_SQL = """
            INSERT INTO A1_EVENT_OUTBOX
              (EVENT_ID, AGGREGATE_TYPE, AGGREGATE_ID, EVENT_TYPE, EVENT_SEQ,
               SCHEMA_VERSION, TRACE_ID, SPAN_ID, SOURCE_SYSTEM, PAYLOAD)
            VALUES (?, ?, ?, ?, SEQ_A1_EVENT.NEXTVAL, '1.0.0', ?, ?, 'APP', ?)
            """;

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final TraceContext traceContext;

    /**
     * {@code MANDATORY} propagation: this method refuses to run without a caller-supplied
     * transaction. If aspect ordering is ever broken, the failure is immediate and loud
     * rather than a silent regression to at-most-once delivery.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public void write(String aggregateType, String aggregateId, String eventType, Object payload) {
        String traceId = traceContext.traceId();
        String spanId  = traceContext.spanId();

        // Jackson 3 (Spring Boot 4) throws unchecked JacksonException rather than the
        // checked JsonProcessingException of Jackson 2. The failure is still allowed to
        // propagate and fail the business transaction: a silently dropped A1 event is a
        // compliance breach, whereas a failed-and-retried payment is not. The asymmetry
        // is deliberate and is the same trade-off Approach 1 makes in its trigger.
        String json = objectMapper.writeValueAsString(payload);

        jdbc.update(INSERT_SQL, uuidToBytes(UUID.randomUUID()), aggregateType, aggregateId,
                    eventType, traceId, spanId, json);
    }

    static byte[] uuidToBytes(UUID uuid) {
        return ByteBuffer.allocate(16)
                .putLong(uuid.getMostSignificantBits())
                .putLong(uuid.getLeastSignificantBits())
                .array();
    }
}

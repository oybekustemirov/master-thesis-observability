package itpu.uz.masterthesisobservability.aq;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.DistributionSummary;
import io.micrometer.core.instrument.MeterRegistry;
import itpu.uz.masterthesisobservability.config.ObservabilityProperties;
import jakarta.jms.Connection;
import jakarta.jms.ConnectionFactory;
import jakarta.jms.Message;
import jakarta.jms.MessageConsumer;
import jakarta.jms.Session;
import jakarta.jms.TextMessage;
import jakarta.jms.Topic;
import lombok.extern.slf4j.Slf4j;
import oracle.jakarta.jms.AQjmsSession;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.context.SmartLifecycle;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;

import static java.nio.charset.StandardCharsets.UTF_8;

/**
 * Approach 1, second half: drains the Oracle AQ durable subscriber and republishes onto Kafka.
 *
 * <p>The first half — the compound trigger and {@code PKG_A1_EVENT} — already gives the
 * property that motivates the approach: the message is enqueued inside the business
 * transaction with {@code visibility => ON_COMMIT}, so it becomes visible exactly when the
 * transaction commits and disappears when it rolls back. There is no dual write and no loss
 * window between the row change and the event. What this class must do is carry that guarantee
 * across the boundary into Kafka without reintroducing one.
 *
 * <h2>Why this is a loop and not {@code @JmsListener}</h2>
 * Spring's listener container commits the JMS session once per message. With a blocking Kafka
 * send inside the listener that is one broker round trip per event, which is precisely the
 * defect measured in {@code OutboxRelay}: it capped the relay at roughly one record per round
 * trip and turned end-to-end latency into a property of the relay rather than of the pattern
 * under test. Batching there cut p50 latency from 7416 ms to 136 ms.
 *
 * <p>Approach 1 has to be given the same treatment or the comparison is rigged. So the bridge
 * dequeues a batch inside one transacted session, pipelines the whole batch to Kafka, waits
 * for every acknowledgement, and only then commits the session. The two relays now differ
 * only in where they read from — a database table versus a queue — which is the difference the
 * thesis actually intends to measure.
 *
 * <h2>Delivery semantics</h2>
 * <ul>
 *   <li>Kafka send fails: the session is rolled back, nothing is dequeued, AQ redelivers.
 *       No loss.</li>
 *   <li>The process dies between the Kafka acknowledgements and {@code session.commit()}: the
 *       messages are redelivered and republished. Duplicates, no loss — at-least-once, with
 *       consumers deduplicating on the {@code eventId} header.</li>
 *   <li>A message that fails {@code max_retries} (5, set in migration V4) is moved by AQ to
 *       the exception queue {@code AQ$_A1_EVT_QT_E} rather than blocking the subscriber. That
 *       is the poison-message path exercised by fault case F8.</li>
 * </ul>
 *
 * <h2>Ordering</h2>
 * One session, one thread. The queue table sorts on {@code ENQ_TIME}, so messages are dequeued
 * in enqueue order, sent to Kafka in that order, and keyed on the aggregate id so all events of
 * one transaction share a partition. The idempotent producer preserves per-partition order
 * across in-flight batches. A second concurrent session would raise throughput and destroy
 * this property, which is why the bridge is deliberately single-threaded — and why its
 * throughput ceiling is reported as a finding rather than tuned away.
 */
@Component
@ConditionalOnProperty(name = "observability.mode", havingValue = "AQ")
@Slf4j
public class AqToKafkaBridge implements SmartLifecycle {

    private final ConnectionFactory connectionFactory;
    private final KafkaTemplate<String, String> kafka;
    private final ObservabilityProperties properties;

    private final Counter bridged;
    private final Counter rollbacks;
    private final DistributionSummary batchSize;

    private volatile boolean running;
    private Thread worker;
    private Connection connection;

    public AqToKafkaBridge(ConnectionFactory aqConnectionFactory,
                           KafkaTemplate<String, String> kafka,
                           MeterRegistry meters,
                           ObservabilityProperties properties) {
        this.connectionFactory = aqConnectionFactory;
        this.kafka = kafka;
        this.properties = properties;
        this.bridged = meters.counter("obsv.aq.bridged");
        this.rollbacks = meters.counter("obsv.aq.rollbacks");
        this.batchSize = DistributionSummary.builder("obsv.aq.batch.size").register(meters);
    }

    @Override
    public void start() {
        try {
            connection = connectionFactory.createConnection();
            // A durable subscriber is identified by its client id plus its name. AQ maps the
            // name onto the subscriber agent added in V4, so the two must agree exactly or the
            // bridge silently creates a SECOND subscriber and reads an empty backlog while the
            // real one grows without bound.
            connection.setClientID(properties.aq().subscriber());
            connection.start();
        } catch (Exception e) {
            throw new IllegalStateException("cannot open the AQ connection", e);
        }
        running = true;
        worker = new Thread(this::drain, "aq-kafka-bridge");
        worker.setDaemon(true);
        worker.start();
        log.info("AQ bridge started: {}.{} -> topic {}",
                properties.aq().queueOwner(), properties.aq().queue(), properties.topic().events());
    }

    private void drain() {
        long timeout = properties.aq().receiveTimeout().toMillis();
        int max = properties.aq().batchSize();

        try (Session session = connection.createSession(true, Session.SESSION_TRANSACTED)) {
            Topic topic = ((AQjmsSession) session)
                    .getTopic(properties.aq().queueOwner(), properties.aq().queue());
            try (MessageConsumer consumer =
                         session.createDurableSubscriber(topic, properties.aq().subscriber())) {

                while (running) {
                    try {
                        Message first = consumer.receive(timeout);
                        if (first == null) {
                            continue;
                        }
                        var batch = new ArrayList<Message>();
                        batch.add(first);
                        // Every receiveNoWait is its own DBMS_AQ.DEQUEUE round trip: AQ JMS has
                        // no array dequeue in the JMS API. That per-message round trip is an
                        // irreducible cost of this approach and is reported as such.
                        while (batch.size() < max) {
                            Message next = consumer.receiveNoWait();
                            if (next == null) {
                                break;
                            }
                            batch.add(next);
                        }
                        publishBatch(batch);
                        session.commit();
                        bridged.increment(batch.size());
                        batchSize.record(batch.size());
                    } catch (Exception e) {
                        if (!running) {
                            break;
                        }
                        rollbacks.increment();
                        // Loud on purpose. A swallowed error here drops A1 events, and the
                        // whole point of the experiment is that such a drop must be visible.
                        log.error("AQ batch failed; rolling back for redelivery", e);
                        safeRollback(session);
                    }
                }
            }
        } catch (Exception e) {
            if (running) {
                log.error("AQ bridge stopped unexpectedly", e);
            }
        }
    }

    private void publishBatch(List<Message> batch) throws Exception {
        var inFlight = new ArrayList<CompletableFuture<?>>(batch.size());
        for (Message message : batch) {
            if (!(message instanceof TextMessage text)) {
                // Not recoverable by retrying: fail the batch so the message reaches the
                // exception queue instead of being discarded here.
                throw new IllegalStateException(
                        "unexpected AQ payload type " + message.getClass().getName());
            }
            inFlight.add(publish(text));
        }
        // Wait for every acknowledgement BEFORE the session commits. Committing first would
        // remove the message from the queue while its Kafka send could still fail — the exact
        // loss window that Approach 1 exists to avoid, reintroduced at the bridge.
        CompletableFuture.allOf(inFlight.toArray(CompletableFuture[]::new)).join();
    }

    private CompletableFuture<?> publish(TextMessage message) throws Exception {
        String aggregateId = message.getStringProperty("aggregateId");
        var record = new ProducerRecord<>(properties.topic().events(), aggregateId, message.getText());
        // Same header set as OutboxRelay, so a consumer cannot tell the two apart and the
        // measured difference is not a payload-convention difference.
        header(record, "eventId", message.getStringProperty("eventId"));
        header(record, "eventType", message.getStringProperty("eventType"));
        header(record, "eventSeq", String.valueOf(message.getIntProperty("eventSeq")));
        header(record, "schemaVersion", message.getStringProperty("schemaVersion"));
        header(record, "sourceSystem", "DB");
        return kafka.send(record);
    }

    private static void header(ProducerRecord<String, String> record, String key, String value) {
        if (value != null) {
            record.headers().add(key, value.getBytes(UTF_8));
        }
    }

    private static void safeRollback(Session session) {
        try {
            session.rollback();
        } catch (Exception e) {
            log.error("AQ rollback failed", e);
        }
    }

    @Override
    public void stop() {
        running = false;
        if (worker != null) {
            worker.interrupt();
            try {
                worker.join(5_000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        try {
            if (connection != null) {
                connection.close();
            }
        } catch (Exception e) {
            log.warn("closing the AQ connection failed", e);
        }
        log.info("AQ bridge stopped");
    }

    @Override
    public boolean isRunning() {
        return running;
    }
}

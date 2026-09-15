package itpu.uz.masterthesisobservability.naive;

import itpu.uz.masterthesisobservability.outbox.A1Event;
import itpu.uz.masterthesisobservability.outbox.EventEmitter;
import tools.jackson.databind.ObjectMapper;
import itpu.uz.masterthesisobservability.config.ObservabilityProperties;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.core.KafkaTemplate;

/**
 * VARIANT B1 — the dual-write anti-pattern, implemented faithfully so it can be measured
 * and refuted rather than merely asserted to be wrong.
 *
 * <p>Two independent defects, both demonstrated by the fault matrix:
 * <ul>
 *   <li><b>Lost events</b> — the send is fire-and-forget from inside the transaction. A JVM
 *       crash after the database commit but before the broker acknowledges destroys the
 *       event, and nothing anywhere records that it ever existed (fault F1).</li>
 *   <li><b>Phantom events</b> — the event is already on the bus when the transaction rolls
 *       back, so consumers act on a payment that never happened. In a bank this is worse
 *       than a lost event: a fraud engine or a customer notification fires on a transaction
 *       that does not exist.</li>
 * </ul>
 */
@RequiredArgsConstructor
@Slf4j
public class DirectKafkaEventEmitter implements EventEmitter {

    private final KafkaTemplate<String, String> kafka;
    private final ObjectMapper objectMapper;
    private final ObservabilityProperties properties;

    @Override
    public void emit(A1Event event) {
        try {
            kafka.send(properties.topic().events(), event.aggregateId(),
                       objectMapper.writeValueAsString(event));
        } catch (Exception e) {
            // Swallowed deliberately: this is what "fire and forget" means in practice, and
            // it is the behaviour under measurement. Do not repair it.
            log.warn("B1 publish failed for {}", event.eventId(), e);
        }
    }
}

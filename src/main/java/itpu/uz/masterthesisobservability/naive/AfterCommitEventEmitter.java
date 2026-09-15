package itpu.uz.masterthesisobservability.naive;

import tools.jackson.databind.ObjectMapper;
import itpu.uz.masterthesisobservability.config.ObservabilityProperties;
import itpu.uz.masterthesisobservability.outbox.A1Event;
import itpu.uz.masterthesisobservability.outbox.EventEmitter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * VARIANT B2 — publish after commit. Strictly better than B1: no phantom events, because
 * nothing is sent unless the transaction actually committed.
 *
 * <p>Still at-most-once. The window between the database commit and the broker acknowledgement
 * is unprotected, and unlike B1 the failure is entirely invisible: the payment succeeded, the
 * event never existed, and no artefact anywhere records the discrepancy. B2 is the variant most
 * likely to be shipped by a competent team that has not thought about crash semantics, which is
 * exactly why the thesis measures it rather than dismissing it.
 */
@RequiredArgsConstructor
@Slf4j
public class AfterCommitEventEmitter implements EventEmitter {

    private final ApplicationEventPublisher publisher;
    private final KafkaTemplate<String, String> kafka;
    private final ObjectMapper objectMapper;
    private final ObservabilityProperties properties;

    @Override
    public void emit(A1Event event) {
        publisher.publishEvent(event);
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onAfterCommit(A1Event event) {
        try {
            kafka.send(properties.topic().events(), event.aggregateId(),
                       objectMapper.writeValueAsString(event));
        } catch (Exception e) {
            log.warn("B2 publish failed for {}", event.eventId(), e);
        }
    }
}

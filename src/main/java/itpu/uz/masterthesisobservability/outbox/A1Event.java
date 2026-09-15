package itpu.uz.masterthesisobservability.outbox;

import java.time.Instant;
import java.util.UUID;

/**
 * The event envelope. Identical in every mode that emits from the application, so the payload
 * on the bus is comparable across modes and the reconciliation query is mode-independent.
 */
public record A1Event(UUID eventId,
                      String eventType,
                      String schemaVersion,
                      Instant occurredAt,
                      String aggregateType,
                      String aggregateId,
                      String sourceSystem,
                      String traceId,
                      Object payload) {

    public static A1Event of(String eventType, String aggregateType, String aggregateId,
                             String traceId, Object payload) {
        return new A1Event(UUID.randomUUID(), eventType, "1.0.0", Instant.now(),
                           aggregateType, aggregateId, "APP", traceId, payload);
    }
}

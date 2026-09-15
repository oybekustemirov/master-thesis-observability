package itpu.uz.masterthesisobservability.outbox;

import lombok.RequiredArgsConstructor;

/** Variant B3 and HYBRID: the event becomes a row in the caller's transaction. Zero loss. */
@RequiredArgsConstructor
public class OutboxEventEmitter implements EventEmitter {

    private final OutboxWriter writer;

    @Override
    public void emit(A1Event event) {
        writer.write(event.aggregateType(), event.aggregateId(), event.eventType(), event);
    }
}

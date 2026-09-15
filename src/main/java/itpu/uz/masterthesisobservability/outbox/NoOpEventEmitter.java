package itpu.uz.masterthesisobservability.outbox;


/**
 * Used by OFF, BASELINE_GT, AQ and CDC.
 *
 * <p>AQ and CDC emit nothing from the application by design — that is precisely their selling
 * point (no application change) and their limitation (no application context). The no-op is
 * therefore a faithful representation of those modes, not a stub.
 */
public class NoOpEventEmitter implements EventEmitter {
    @Override
    public void emit(A1Event event) { }
}

package itpu.uz.masterthesisobservability.outbox;

/**
 * Emission strategy, selected once by {@code observability.mode}.
 *
 * <p>Keeping the strategies behind one interface means every mode traverses an identical
 * joinpoint and an identical business code path; only the emission differs. That is what makes
 * the throughput and latency deltas attributable to the mechanism rather than to incidental
 * differences in how each variant was wired.
 */
public interface EventEmitter {
    void emit(A1Event event);
}

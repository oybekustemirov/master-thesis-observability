package itpu.uz.masterthesisobservability.config;

/**
 * The experiment switch. Exactly one mode is active per run; the harness restarts the
 * application between modes so that no JIT or cache state leaks across measurements.
 *
 * <p>Three baselines rather than one, so that the cost of the measuring apparatus itself is
 * quantified instead of hidden:
 * <ul>
 *   <li>{@link #OFF} — no ground truth, no events. True zero-instrumentation throughput.</li>
 *   <li>{@link #BASELINE_GT} — ground-truth trigger only. The apparatus cost.</li>
 *   <li>everything else — apparatus + that mode's mechanism.</li>
 * </ul>
 * Reported cost of a mode is {@code mode - BASELINE_GT}; the apparatus cost
 * {@code BASELINE_GT - OFF} is reported separately as a result in its own right.
 */
public enum ObservabilityMode {

    /** No instrumentation at all. Establishes the raw business throughput ceiling. */
    OFF(false, false),

    /** Control instrument only. Isolates what the measurement itself costs. */
    BASELINE_GT(true, false),

    /** Approach 1: compound trigger to PKG_A1_EVENT to DBMS_AQ, bridged to Kafka over AQ-JMS. */
    AQ(true, true),

    /** Approach 2 naive: @AfterReturning publishes directly. Dual write; retained to be refuted. */
    WRAPPER_B1(true, false),

    /** Approach 2: publishes after commit. No phantom events, but an unprotected loss window. */
    WRAPPER_B2(true, false),

    /** Approach 2 correct: AOP writes a transactional outbox row; a polling relay publishes it. */
    WRAPPER_B3(true, false),

    /** Approach 3: Debezium mines TXN_A1 directly. No application-side event code at all. */
    CDC(true, false),

    /** Recommended: outbox written in-transaction by app and PL/SQL, relayed by Debezium. */
    HYBRID(true, false);

    private final boolean groundTruthTrigger;
    private final boolean aqTrigger;

    ObservabilityMode(boolean groundTruthTrigger, boolean aqTrigger) {
        this.groundTruthTrigger = groundTruthTrigger;
        this.aqTrigger = aqTrigger;
    }

    public boolean requiresGroundTruthTrigger() { return groundTruthTrigger; }
    public boolean requiresAqTrigger()          { return aqTrigger; }

    /**
     * The table that must carry ALL-column supplemental logging in this mode, or {@code null}.
     *
     * <p>This is switched per mode rather than enabled once and left on, because ALL-column
     * supplemental logging makes Oracle write the entire row to redo on every UPDATE whether or
     * not anyone is mining it. Leaving it on {@code TXN_A1} permanently would add Approach 3's
     * redo cost to the measurement of every other approach — including the baselines — and the
     * comparison would understate how much CDC actually costs the database. It is part of what
     * Approach 3 costs, so it is charged to Approach 3.
     *
     * <p>Without it the connector does not fail. It emits structurally valid change events in
     * which every column absent from the redo record is filled with a type default: measured
     * here as {@code TXN_ID "0"} and {@code TXN_REF ""} on every UPDATE, while the INSERT
     * events were complete. The topic then carries exactly as many messages as there were state
     * transitions, so any check based on counting events reports a perfect result while
     * two-thirds of the events are unusable.
     */
    public String supplementalLoggingTable() {
        return switch (this) {
            case CDC    -> "TXN_A1";
            case HYBRID -> "A1_EVENT_OUTBOX";
            default     -> null;
        };
    }

    /** True when the application itself must write outbox rows (as opposed to a trigger). */
    public boolean requiresOutboxWrites()       { return this == WRAPPER_B3 || this == HYBRID; }

    /** True when the application publishes to Kafka directly rather than through a relay. */
    public boolean publishesDirectly()          { return this == WRAPPER_B1 || this == WRAPPER_B2; }
}

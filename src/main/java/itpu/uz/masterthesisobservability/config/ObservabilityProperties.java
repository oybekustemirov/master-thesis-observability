package itpu.uz.masterthesisobservability.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

import java.time.Duration;

@ConfigurationProperties(prefix = "observability")
public record ObservabilityProperties(

        @DefaultValue("OFF") ObservabilityMode mode,
        @DefaultValue Outbox outbox,
        @DefaultValue Aq aq,
        @DefaultValue Topic topic,
        /** When false, the harness manages trigger state itself and startup leaves it alone. */
        @DefaultValue("true") boolean manageTriggers) {

    public record Outbox(
            @DefaultValue("200ms") Duration pollInterval,
            @DefaultValue("500") int batchSize,
            /** Retention for published outbox rows; the purge job drops older partitions. */
            @DefaultValue("7") int retentionDays) {}

    /**
     * Settings for the Approach 1 bridge. The batch size deliberately matches
     * {@link Outbox#batchSize()}: the two relays must differ only in where they read from,
     * otherwise the comparison measures two implementations rather than two mechanisms.
     */
    public record Aq(
            @DefaultValue("A1_EVT_Q") String queue,
            /** Must match the AQ subscriber agent created in migration V4. */
            @DefaultValue("OBSERVABILITY_BRIDGE") String subscriber,
            @DefaultValue("OBSV") String queueOwner,
            @DefaultValue("500") int batchSize,
            /** How long an idle bridge blocks in DBMS_AQ.DEQUEUE before looping. */
            @DefaultValue("500ms") Duration receiveTimeout) {}

    public record Topic(
            @DefaultValue("bank.a1.transaction.events") String events,
            /** Credit-application stage events. A separate topic because they are a different
                aggregate with a different consumer; routing both onto one topic would force
                every consumer to filter and would make the A1 reconciliation count credit
                events as phantoms. */
            @DefaultValue("bank.credit.application.events") String credit) {}

    /** Topic for an aggregate type, defaulting to the A1 topic for anything unrecognised. */
    public String topicFor(String aggregateType) {
        return "credit.application".equals(aggregateType) ? topic().credit() : topic().events();
    }
}

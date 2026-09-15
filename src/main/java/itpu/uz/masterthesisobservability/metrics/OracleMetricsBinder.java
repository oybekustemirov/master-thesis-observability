package itpu.uz.masterthesisobservability.metrics;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.binder.MeterBinder;
import itpu.uz.masterthesisobservability.config.ObservabilityProperties;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicLong;

/**
 * Publishes the database-side quantities the results chapter needs, so that Oracle, the
 * application and Debezium all land on one Prometheus timeline and can be correlated without
 * manual alignment.
 *
 * <p>Values are refreshed on a schedule rather than on scrape, because a scrape-time query
 * would put Prometheus's cadence on the measured database and pollute the very numbers being
 * collected.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class OracleMetricsBinder implements MeterBinder {

    private final JdbcTemplate jdbc;
    private final ObservabilityProperties properties;

    private final AtomicLong outboxPending  = new AtomicLong();
    private final AtomicLong outboxTotal    = new AtomicLong();
    private final AtomicLong aqDepth        = new AtomicLong();
    private final AtomicLong aqExceptions   = new AtomicLong();
    private final AtomicLong groundTruth    = new AtomicLong();
    private final AtomicLong redoSize       = new AtomicLong();
    private final AtomicLong userCommits    = new AtomicLong();
    private final AtomicLong currentScn     = new AtomicLong();

    @Override
    public void bindTo(MeterRegistry registry) {
        String mode = properties.mode().name();
        gauge(registry, "obsv.outbox.pending", outboxPending, mode,
              "Unpublished outbox rows: the backlog that absorbs backpressure in variant B3");
        gauge(registry, "obsv.outbox.total", outboxTotal, mode, "Outbox rows written");
        gauge(registry, "obsv.aq.depth", aqDepth, mode, "Messages awaiting dequeue in the AQ queue table");
        gauge(registry, "obsv.aq.exception_queue", aqExceptions, mode,
              "Messages moved to the AQ exception queue: silent loss unless monitored");
        gauge(registry, "obsv.ground_truth.transitions", groundTruth, mode,
              "Committed A1 state transitions recorded by the control instrument");
        gauge(registry, "obsv.oracle.redo_size_bytes", redoSize, mode,
              "V$SYSSTAT redo size: the basis of the redo-amplification metric");
        gauge(registry, "obsv.oracle.user_commits", userCommits, mode, "V$SYSSTAT user commits");
        gauge(registry, "obsv.oracle.current_scn", currentScn, mode,
              "Database SCN, for comparison against the Debezium committed offset");
    }

    private void gauge(MeterRegistry registry, String name, AtomicLong value,
                       String mode, String description) {
        Gauge.builder(name, value, AtomicLong::doubleValue)
                .description(description)
                .tag("mode", mode)
                .register(registry);
    }

    @org.springframework.scheduling.annotation.Scheduled(fixedDelay = 2000)
    void refresh() {
        set(outboxPending, "SELECT COUNT(*) FROM A1_EVENT_OUTBOX WHERE PUBLISHED_AT IS NULL");
        set(outboxTotal,   "SELECT COUNT(*) FROM A1_EVENT_OUTBOX");
        set(groundTruth,   "SELECT COUNT(*) FROM GROUND_TRUTH");
        set(aqDepth,       "SELECT COUNT(*) FROM A1_EVT_QT");
        set(aqExceptions,  "SELECT COUNT(*) FROM AQ$_A1_EVT_QT_E");
        set(currentScn,    "SELECT CURRENT_SCN FROM V$DATABASE");
        set(redoSize,      "SELECT VALUE FROM V$SYSSTAT WHERE NAME = 'redo size'");
        set(userCommits,   "SELECT VALUE FROM V$SYSSTAT WHERE NAME = 'user commits'");
    }

    private void set(AtomicLong target, String sql) {
        try {
            Long v = jdbc.queryForObject(sql, Long.class);
            target.set(v == null ? 0L : v);
        } catch (Exception e) {
            // A missing object (for example the AQ exception queue before V4 has run) must not
            // take down metrics collection for everything else.
            log.trace("metric query failed: {}", sql, e);
        }
    }
}

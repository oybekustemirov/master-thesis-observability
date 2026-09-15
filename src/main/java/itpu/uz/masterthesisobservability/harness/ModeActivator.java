package itpu.uz.masterthesisobservability.harness;

import itpu.uz.masterthesisobservability.config.ObservabilityProperties;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * Puts the database into exactly the state the active mode requires, at startup.
 *
 * <p>Both capture triggers ship DISABLED. Leaving trigger state to manual operation is how an
 * experiment silently measures two mechanisms at once and produces results nobody can explain
 * afterwards, so it is automated and logged here instead.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class ModeActivator implements ApplicationRunner {

    private final JdbcTemplate jdbc;
    private final ObservabilityProperties properties;

    @Override
    public void run(ApplicationArguments args) {
        if (!properties.manageTriggers()) {
            log.info("observability.manage-triggers=false — trigger state left untouched");
            return;
        }
        var mode = properties.mode();
        setTrigger("TRG_GROUND_TRUTH", mode.requiresGroundTruthTrigger());
        setTrigger("TRG_TXN_A1_AQ",    mode.requiresAqTrigger());

        String logged = mode.supplementalLoggingTable();
        for (String table : SUPPLEMENTAL_CANDIDATES) {
            setSupplementalLogging(table, table.equals(logged));
        }
        log.info("mode={} activated: groundTruth={} aqCapture={} supplementalLogging={}",
                mode, mode.requiresGroundTruthTrigger(), mode.requiresAqTrigger(),
                logged == null ? "none" : logged);
    }

    /**
     * Every table any mode may need to mine. Listed explicitly so that the activator turns
     * logging OFF on the tables the active mode does not capture, not merely ON on the one it
     * does — otherwise a CDC run would leave TXN_A1 logging every column for the wrapper run
     * that followed it, and that run's redo figure would silently include Approach 3's cost.
     */
    private static final String[] SUPPLEMENTAL_CANDIDATES = {"TXN_A1", "A1_EVENT_OUTBOX"};

    /**
     * ALL-column supplemental logging is expressed as an implicit log group on the table, so
     * the current state is read from USER_LOG_GROUPS rather than assumed. Issuing ADD when it
     * is already present raises ORA-32588, and DROP when it is absent raises ORA-32589; either
     * would abort startup on the second run of the same mode.
     */
    private void setSupplementalLogging(String table, boolean enabled) {
        Integer present = jdbc.queryForObject(
                "SELECT COUNT(*) FROM USER_LOG_GROUPS "
              + "WHERE TABLE_NAME = ? AND LOG_GROUP_TYPE = 'ALL COLUMN LOGGING'",
                Integer.class, table);
        boolean already = present != null && present > 0;
        if (already == enabled) {
            return;
        }
        jdbc.execute("ALTER TABLE " + table
                   + (enabled ? " ADD" : " DROP") + " SUPPLEMENTAL LOG DATA (ALL) COLUMNS");
        log.info("supplemental logging on {} -> {}", table, enabled ? "ALL COLUMNS" : "off");
    }

    private void setTrigger(String name, boolean enabled) {
        // DDL cannot be parameterised; the names are compile-time constants, not user input.
        jdbc.execute("ALTER TRIGGER " + name + (enabled ? " ENABLE" : " DISABLE"));
        log.debug("trigger {} -> {}", name, enabled ? "ENABLED" : "DISABLED");
    }
}

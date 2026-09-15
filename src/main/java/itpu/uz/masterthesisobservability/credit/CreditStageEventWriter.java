package itpu.uz.masterthesisobservability.credit;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.Map;

/**
 * Writes one row of the process event log, inside the caller's transaction.
 *
 * <p>MANDATORY propagation for the same reason the outbox writer uses it: if the stage row and
 * the business state ever stop sharing a commit, the log develops gaps that look exactly like a
 * case skipping a stage, and every duration computed across that gap is silently wrong.
 */
@Component
@RequiredArgsConstructor
public class CreditStageEventWriter {

    private static final String INSERT = """
            INSERT INTO CREDIT_STAGE_EVENT
              (APP_ID, FROM_STAGE, TO_STAGE, ENTERED_AT, PICKED_UP_AT, COMPLETED_AT,
               ACTOR_ID, ACTOR_ROLE, BRANCH_CODE, IS_REWORK)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """;

    private final JdbcTemplate jdbc;

    @Transactional(propagation = Propagation.MANDATORY)
    public void record(Long appId, String fromStage, String toStage,
                       Instant enteredAt, Instant pickedUpAt, Instant completedAt,
                       String actorId, String actorRole, String branch, boolean rework) {
        jdbc.update(INSERT, appId, fromStage, toStage,
                Timestamp.from(enteredAt),
                pickedUpAt == null ? null : Timestamp.from(pickedUpAt),
                Timestamp.from(completedAt),
                actorId, actorRole, branch, rework ? 1 : 0);
    }

    /** Stage metadata, read from the table so the process definition stays configuration. */
    @Transactional(propagation = Propagation.MANDATORY, readOnly = true)
    public Map<String, Object> stage(String code) {
        var rows = jdbc.queryForList(
                "SELECT STAGE_CODE, STAGE_NAME, STAGE_TYPE, SEQ FROM CREDIT_STAGE WHERE STAGE_CODE = ?",
                code);
        if (rows.isEmpty()) {
            throw new UnknownStageException(code);
        }
        return rows.get(0);
    }
}

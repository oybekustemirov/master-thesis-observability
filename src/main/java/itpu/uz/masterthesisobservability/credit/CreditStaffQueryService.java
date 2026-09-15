package itpu.uz.masterthesisobservability.credit;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;

/**
 * Per-employee analysis: which member of staff spends how much time on each application.
 *
 * <p>Modelled on the report a bank already runs nightly, and deliberately different from it in
 * four places where that report cannot answer the question it is asked.
 *
 * <p><b>1. Work time exists here.</b> The existing report groups its events and projects a single
 * {@code LAST_EVENT_TIME}; the per-action begin and end are computed in an inner block and then
 * dropped. Duration therefore has to be reconstructed downstream by subtracting consecutive rows,
 * which is exactly the arithmetic that silently absorbs a missing event. Here the interval is
 * carried on the event itself, so a duration is read rather than inferred.
 *
 * <p><b>2. Queue is separated from work, and is not charged to the employee.</b> The case sitting
 * in a shared queue before anyone opened it is a capacity property of the role, not a performance
 * property of whoever eventually picked it up. Reported side by side, never summed into one
 * "time spent" column — the sum is what turns a staffing problem into an accusation.
 *
 * <p><b>3. The person charged is the person named.</b> The existing report names
 * {@code NVL(prev_user_id, modified_by)} but prices every action from {@code modified_by} alone,
 * so when those differ the cost of an action lands on a different employee than the row displays.
 * Here both come from {@code ACTOR_ID}.
 *
 * <p><b>4. Unknown cost stays unknown.</b> That report substitutes the literal 1000 for a missing
 * salary, mixing measured and invented values in one column with nothing to tell them apart. A
 * role with no row in {@code CREDIT_ROLE_COST} yields NULL here and renders as an em dash.
 */
@Service
@RequiredArgsConstructor
public class CreditStaffQueryService {

    /** Only a transition somebody actually picked up carries work; the rest belong to a customer,
        an outside organisation or the committee calendar and have no owner to attribute. */
    private static final String PICKED_UP = " WHERE e.PICKED_UP_AT IS NOT NULL AND e.ACTOR_ID IS NOT NULL ";

    private static final String WORK_H =
            "(CAST(e.COMPLETED_AT AS DATE) - CAST(e.PICKED_UP_AT AS DATE)) * 24";
    private static final String QUEUE_H =
            "(CAST(e.PICKED_UP_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24";

    private final JdbcTemplate jdbc;

    @Transactional(readOnly = true)
    public Map<String, Object> staff() {
        var rows = jdbc.queryForList("""
                SELECT e.ACTOR_ID, e.ACTOR_ROLE, MAX(s.BRANCH_CODE) AS BRANCH_CODE,
                       COUNT(DISTINCT e.APP_ID) AS APPLICATIONS,
                       COUNT(*) AS TRANSITIONS,
                       ROUND(SUM(%1$s), 1) AS WORK_H,
                       ROUND(SUM(%1$s) / COUNT(DISTINCT e.APP_ID), 2) AS WORK_H_PER_APP,
                       ROUND(MEDIAN(%1$s), 2) AS MEDIAN_WORK_H,
                       ROUND(MEDIAN(%2$s), 2) AS MEDIAN_QUEUE_H,
                       ROUND(100 * SUM(e.IS_REWORK) / COUNT(*), 1) AS REWORK_PCT,
                       ROUND(SUM(%1$s) * MAX(c.MONTHLY_COST * c.OVERHEAD_FACTOR / c.HOURS_PER_MONTH)) AS COST,
                       MAX(c.CURRENCY) AS CURRENCY
                  FROM CREDIT_STAGE_EVENT e
                  JOIN CREDIT_STAFF s ON s.STAFF_ID = e.ACTOR_ID
                  LEFT JOIN CREDIT_ROLE_COST c ON c.STAFF_ROLE = e.ACTOR_ROLE
                 %3$s
                 GROUP BY e.ACTOR_ID, e.ACTOR_ROLE
                 ORDER BY e.ACTOR_ROLE, SUM(%1$s) DESC
                """.formatted(WORK_H, QUEUE_H, PICKED_UP));

        // Ranked WITHIN the role. An underwriter and an operations clerk do different work, and a
        // league table that mixes them measures the job, not the person.
        var roles = jdbc.queryForList("""
                SELECT e.ACTOR_ROLE,
                       COUNT(DISTINCT e.ACTOR_ID) AS STAFF,
                       COUNT(DISTINCT e.APP_ID) AS APPLICATIONS,
                       COUNT(*) AS TRANSITIONS,
                       ROUND(SUM(%1$s), 1) AS WORK_H,
                       ROUND(MEDIAN(%1$s), 2) AS MEDIAN_WORK_H,
                       ROUND(MEDIAN(%2$s), 2) AS MEDIAN_QUEUE_H,
                       ROUND(SUM(%2$s), 1) AS QUEUE_H,
                       ROUND(SUM(%1$s) * MAX(c.MONTHLY_COST * c.OVERHEAD_FACTOR / c.HOURS_PER_MONTH)) AS COST,
                       MAX(c.CURRENCY) AS CURRENCY
                  FROM CREDIT_STAGE_EVENT e
                  LEFT JOIN CREDIT_ROLE_COST c ON c.STAFF_ROLE = e.ACTOR_ROLE
                 %3$s
                 GROUP BY e.ACTOR_ROLE
                 ORDER BY SUM(%1$s) DESC
                """.formatted(WORK_H, QUEUE_H, PICKED_UP));

        // The spread between the fastest and the slowest member of a role, next to the queue that
        // every case in that role waits in regardless. The comparison is the point: a three-fold
        // spread worth two hours per case sits beside a queue worth twenty-five.
        var spread = jdbc.queryForList("""
                SELECT ACTOR_ROLE,
                       ROUND(MIN(MED), 2) AS FASTEST_H, ROUND(MAX(MED), 2) AS SLOWEST_H,
                       ROUND(MAX(MED) / NULLIF(MIN(MED), 0), 1) AS RATIO,
                       ROUND(MAX(MED) - MIN(MED), 2) AS GAP_H
                  FROM (SELECT e.ACTOR_ROLE, e.ACTOR_ID, MEDIAN(%1$s) AS MED
                          FROM CREDIT_STAGE_EVENT e %2$s
                         GROUP BY e.ACTOR_ROLE, e.ACTOR_ID)
                 GROUP BY ACTOR_ROLE
                """.formatted(WORK_H, PICKED_UP));

        var totals = jdbc.queryForMap("""
                SELECT COUNT(DISTINCT e.ACTOR_ID) AS STAFF,
                       COUNT(*) AS TRANSITIONS,
                       ROUND(SUM(%1$s), 1) AS WORK_H,
                       ROUND(SUM(%2$s), 1) AS QUEUE_H
                  FROM CREDIT_STAGE_EVENT e %3$s
                """.formatted(WORK_H, QUEUE_H, PICKED_UP));

        return Map.of("staff", rows, "roles", roles, "spread", spread, "totals", totals,
                "cost", jdbc.queryForList("SELECT * FROM CREDIT_ROLE_COST ORDER BY STAFF_ROLE"));
    }

    /** Every application one member of staff touched, with the time they spent on each. This is
        the question asked literally — "which employee spent how long on this application". */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> byStaff(String staffId) {
        return jdbc.queryForList("""
                SELECT a.APP_REF, a.PRODUCT, a.AMOUNT, a.CURRENCY,
                       e.TO_STAGE, st.STAGE_NAME,
                       ROUND(%1$s, 2) AS WORK_H, ROUND(%2$s, 2) AS QUEUE_H,
                       e.IS_REWORK, e.COMPLETED_AT
                  FROM CREDIT_STAGE_EVENT e
                  JOIN CREDIT_APPLICATION a ON a.APP_ID = e.APP_ID
                  JOIN CREDIT_STAGE st ON st.STAGE_CODE = e.TO_STAGE
                 %3$s AND e.ACTOR_ID = ?
                 ORDER BY e.COMPLETED_AT DESC
                """.formatted(WORK_H, QUEUE_H, PICKED_UP), staffId);
    }
}

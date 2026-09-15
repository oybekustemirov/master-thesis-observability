package itpu.uz.masterthesisobservability.credit;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;

/**
 * Read side of the process view: what a manager or an auditor opens the page to see.
 *
 * <p>The classification of time lives here, in ONE place, and is shared by the timeline view and
 * the aggregate view. Two implementations of "is this waiting or working" drift apart within a
 * week, and a page whose summary disagrees with its own detail is worse than no page.
 */
@Service
@RequiredArgsConstructor
public class CreditQueryService {

    /**
     * Hours the case spent in a stage, split by who was holding it.
     *
     * <p>Only a HUMAN stage where somebody picked the case up contains work. Everywhere else the
     * clock runs on a party that is not a bank employee — the applicant, a valuation company, a
     * state register, or a committee that is not in the room. Counting those as "work" is the
     * single easiest way to produce a report that says the opposite of the truth.
     */
    private static final String CLASSIFY = """
              CASE
                WHEN s.STAGE_TYPE = 'HUMAN' AND e.PICKED_UP_AT IS NOT NULL
                  THEN (CAST(e.PICKED_UP_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24
                WHEN s.STAGE_TYPE = 'HUMAN' THEN 0
                ELSE 0
              END AS QUEUE_H,
              CASE
                WHEN s.STAGE_TYPE = 'HUMAN' AND e.PICKED_UP_AT IS NOT NULL
                  THEN (CAST(e.COMPLETED_AT AS DATE) - CAST(e.PICKED_UP_AT AS DATE)) * 24
                WHEN s.STAGE_TYPE = 'HUMAN'
                  THEN (CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24
                ELSE 0
              END AS WORK_H,
              CASE WHEN s.STAGE_TYPE <> 'HUMAN'
                   THEN (CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24
                   ELSE 0 END AS OTHER_H,
              (CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24 AS TOTAL_H
            """;

    private final JdbcTemplate jdbc;

    @Transactional(readOnly = true)
    public List<Map<String, Object>> applications(int limit, String search) {
        String where = (search == null || search.isBlank()) ? ""
                : " WHERE UPPER(a.APP_REF) LIKE UPPER(?) OR UPPER(a.CUSTOMER_REF) LIKE UPPER(?) ";
        String sql = """
                SELECT a.APP_REF, a.CUSTOMER_REF, a.PRODUCT, a.AMOUNT, a.CURRENCY, a.CHANNEL,
                       a.BRANCH_CODE, a.CURRENT_STAGE, a.OUTCOME, a.HAS_COLLATERAL,
                       a.SUBMITTED_AT, a.CLOSED_AT,
                       -- Elapsed time comes from the EVENT LOG, not from the application row.
                       -- The log is the source of truth for the process: it knows when the case
                       -- entered its first stage and left its last. Deriving it from
                       -- SUBMITTED_AT/CLOSED_AT reported 0 days for cases whose own timeline
                       -- showed six, because those columns are stamped at write time while the
                       -- stage intervals carry the real dates.
                       (SELECT ROUND((CAST(MAX(e.COMPLETED_AT) AS DATE)
                                      - CAST(MIN(e.ENTERED_AT) AS DATE)), 2)
                          FROM CREDIT_STAGE_EVENT e WHERE e.APP_ID = a.APP_ID) AS ELAPSED_DAYS,
                       (SELECT COUNT(*) FROM CREDIT_STAGE_EVENT e WHERE e.APP_ID = a.APP_ID) AS STEPS,
                       (SELECT COUNT(*) FROM CREDIT_STAGE_EVENT e
                         WHERE e.APP_ID = a.APP_ID AND e.IS_REWORK = 1) AS REWORK_STEPS
                  FROM CREDIT_APPLICATION a
                """ + where + " ORDER BY a.SUBMITTED_AT DESC FETCH FIRST " + limit + " ROWS ONLY";
        return (search == null || search.isBlank())
                ? jdbc.queryForList(sql)
                : jdbc.queryForList(sql, "%" + search + "%", "%" + search + "%");
    }

    /** One application's full path, in order, with each interval attributed. */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> timeline(String appRef) {
        return jdbc.queryForList("""
                SELECT e.TO_STAGE, s.STAGE_NAME, s.STAGE_TYPE, e.FROM_STAGE,
                       e.ENTERED_AT, e.PICKED_UP_AT, e.COMPLETED_AT,
                       e.ACTOR_ID, e.ACTOR_ROLE, e.IS_REWORK,
                """ + CLASSIFY + """
                  FROM CREDIT_STAGE_EVENT e
                  JOIN CREDIT_STAGE s ON s.STAGE_CODE = e.TO_STAGE
                  JOIN CREDIT_APPLICATION a ON a.APP_ID = e.APP_ID
                 WHERE a.APP_REF = ?
                 ORDER BY e.COMPLETED_AT, e.EVENT_ID
                """, appRef);
    }

    /** Where the time goes across every application. */
    @Transactional(readOnly = true)
    public Map<String, Object> summary() {
        var ownership = jdbc.queryForList("""
                SELECT owner, ROUND(SUM(hrs), 1) AS HOURS
                  FROM (
                    SELECT CASE s.STAGE_TYPE
                             WHEN 'CUSTOMER'  THEN 'Mijozni kutish'
                             WHEN 'EXTERNAL'  THEN 'Tashqi tomon'
                             WHEN 'COMMITTEE' THEN 'Qo''mita kalendari'
                             WHEN 'HUMAN'     THEN 'Bank navbati'
                             ELSE 'Avtomatik' END AS owner,
                           CASE WHEN s.STAGE_TYPE = 'HUMAN' AND e.PICKED_UP_AT IS NOT NULL
                                  THEN (CAST(e.PICKED_UP_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24
                                WHEN s.STAGE_TYPE = 'HUMAN' THEN 0
                                ELSE (CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24
                           END AS hrs
                      FROM CREDIT_STAGE_EVENT e
                      JOIN CREDIT_STAGE s ON s.STAGE_CODE = e.TO_STAGE
                    UNION ALL
                    SELECT 'Bank xodimi ishlayapti',
                           (CAST(e.COMPLETED_AT AS DATE) - CAST(e.PICKED_UP_AT AS DATE)) * 24
                      FROM CREDIT_STAGE_EVENT e
                      JOIN CREDIT_STAGE s ON s.STAGE_CODE = e.TO_STAGE
                     WHERE e.PICKED_UP_AT IS NOT NULL AND s.STAGE_TYPE = 'HUMAN')
                 GROUP BY owner HAVING SUM(hrs) > 0 ORDER BY SUM(hrs) DESC
                """);

        var stages = jdbc.queryForList("""
                SELECT s.STAGE_CODE, s.STAGE_NAME, s.STAGE_TYPE, s.SEQ, COUNT(*) AS TRANSITIONS,
                       ROUND(SUM((CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24), 1) AS TOTAL_H,
                       ROUND(MEDIAN((CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24), 2) AS MEDIAN_H,
                       ROUND(MEDIAN(CASE WHEN e.PICKED_UP_AT IS NULL THEN NULL ELSE
                         (CAST(e.PICKED_UP_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24 END), 2) AS MEDIAN_QUEUE_H,
                       ROUND(MEDIAN(CASE WHEN e.PICKED_UP_AT IS NULL THEN NULL ELSE
                         (CAST(e.COMPLETED_AT AS DATE) - CAST(e.PICKED_UP_AT AS DATE)) * 24 END), 2) AS MEDIAN_WORK_H
                  FROM CREDIT_STAGE_EVENT e
                  JOIN CREDIT_STAGE s ON s.STAGE_CODE = e.TO_STAGE
                 GROUP BY s.STAGE_CODE, s.STAGE_NAME, s.STAGE_TYPE, s.SEQ
                 ORDER BY SUM((CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24) DESC
                """);

        var outcomes = jdbc.queryForList("""
                SELECT NVL(OUTCOME, 'JARAYONDA') AS OUTCOME, COUNT(*) AS APPLICATIONS,
                       ROUND(MEDIAN(CAST(NVL(CLOSED_AT, SYSTIMESTAMP) AS DATE)
                                    - CAST(SUBMITTED_AT AS DATE)), 2) AS MEDIAN_DAYS
                  FROM CREDIT_APPLICATION GROUP BY OUTCOME ORDER BY COUNT(*) DESC
                """);

        var totals = jdbc.queryForMap("""
                SELECT (SELECT COUNT(*) FROM CREDIT_APPLICATION) AS APPLICATIONS,
                       (SELECT COUNT(*) FROM CREDIT_STAGE_EVENT) AS EVENTS,
                       (SELECT COUNT(*) FROM CREDIT_STAGE) AS STAGES
                  FROM dual
                """);

        return Map.of("ownership", ownership, "stages", stages,
                      "outcomes", outcomes, "totals", totals);
    }

    /** The process definition itself — what the documentation panel shows. */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> stageDefinitions() {
        return jdbc.queryForList(
                "SELECT STAGE_CODE, STAGE_NAME, STAGE_TYPE, SEQ, SLA_HOURS "
              + "FROM CREDIT_STAGE ORDER BY SEQ");
    }
}

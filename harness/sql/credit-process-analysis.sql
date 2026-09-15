-- Process analysis: where does the time in a credit application actually go?
--
-- Four questions, each answered separately because they have different remedies:
--   1. Which stage consumes the most total elapsed time?
--   2. Within a stage, is that time WAITING or WORKING?
--   3. Whose time is it — the bank's, or the applicant's?
--   4. How much of it is rework, which no stage average will show?
--
-- Spooled as CSV so the reporting layer never re-derives a number the database already computed.
SET LINESIZE 400 PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TRIMSPOOL ON TERMOUT OFF
WHENEVER SQLERROR EXIT 1
ALTER SESSION SET CURRENT_SCHEMA = OBSV;

-- Oracle interval arithmetic gives INTERVAL DAY TO SECOND; every duration below is converted to
-- hours through the same expression so the figures are directly comparable.
SPOOL /tmp/credit_stage_summary.csv
SELECT 'stage,stage_name,stage_type,seq,transitions,median_queue_h,p90_queue_h,'
    || 'median_work_h,p90_work_h,median_total_h,p90_total_h,total_hours,rework_share' FROM dual;
-- Attribution is by TO_STAGE. An event means "the case was in TO_STAGE from ENTERED_AT until
-- COMPLETED_AT, then moved on", so the interval belongs to TO_STAGE. Attributing it to FROM_STAGE
-- instead credited 'Ariza kiritish' with the applicant's document wait and left the committee
-- queue — the largest structural delay in the process — showing 1 251 hours instead of its real
-- share.
SELECT s.STAGE_CODE || ',' || s.STAGE_NAME || ',' || s.STAGE_TYPE || ',' || s.SEQ || ','
    || COUNT(*) || ','
    || ROUND(MEDIAN(CASE WHEN e.PICKED_UP_AT IS NULL THEN 0 ELSE
         (CAST(e.PICKED_UP_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24 END), 3) || ','
    || ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY
         CASE WHEN e.PICKED_UP_AT IS NULL THEN 0 ELSE
           (CAST(e.PICKED_UP_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24 END), 3) || ','
    || ROUND(MEDIAN(
         (CAST(e.COMPLETED_AT AS DATE) - CAST(NVL(e.PICKED_UP_AT, e.ENTERED_AT) AS DATE)) * 24), 3) || ','
    || ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY
         (CAST(e.COMPLETED_AT AS DATE) - CAST(NVL(e.PICKED_UP_AT, e.ENTERED_AT) AS DATE)) * 24), 3) || ','
    || ROUND(MEDIAN((CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24), 3) || ','
    || ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY
         (CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24), 3) || ','
    || ROUND(SUM((CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24), 1) || ','
    || ROUND(100 * SUM(e.IS_REWORK) / COUNT(*), 1)
  FROM CREDIT_STAGE_EVENT e
  JOIN CREDIT_STAGE s ON s.STAGE_CODE = e.TO_STAGE
 GROUP BY s.STAGE_CODE, s.STAGE_NAME, s.STAGE_TYPE, s.SEQ
 ORDER BY s.SEQ;
SPOOL OFF

-- End-to-end, by outcome.
SPOOL /tmp/credit_outcomes.csv
SELECT 'outcome,applications,median_days,p90_days,share_pct' FROM dual;
SELECT NVL(a.OUTCOME, 'IN_PROGRESS') || ',' || COUNT(*) || ','
    || ROUND(MEDIAN((CAST(a.CLOSED_AT AS DATE) - CAST(a.SUBMITTED_AT AS DATE))), 2) || ','
    || ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY
         (CAST(a.CLOSED_AT AS DATE) - CAST(a.SUBMITTED_AT AS DATE))), 2) || ','
    || ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)
  FROM CREDIT_APPLICATION a
 GROUP BY a.OUTCOME
 ORDER BY COUNT(*) DESC;
SPOOL OFF

-- Whose time is it? The distinction that decides whether the bank can do anything about it,
-- and the reason the stage vocabulary carries five types rather than three.
--
-- A queue and a committee calendar are both "waiting", and treating them alike would be the
-- costliest mistake this analysis could make: queue time falls when capacity rises, and committee
-- time does not move at all until somebody schedules another sitting.
SPOOL /tmp/credit_ownership.csv
SELECT 'owner,total_hours,share_pct' FROM dual;
SELECT owner || ',' || ROUND(hrs, 1) || ',' || ROUND(100 * hrs / SUM(hrs) OVER (), 1)
  FROM (
    SELECT CASE s.STAGE_TYPE
             WHEN 'CUSTOMER'  THEN 'Mijozni kutish'
             WHEN 'EXTERNAL'  THEN 'Tashqi tomon - baholash / notarius / davlat bazasi'
             WHEN 'COMMITTEE' THEN 'Qo''mita yig''ilishini kutish'
             WHEN 'HUMAN'     THEN 'Bank navbati - hech kim tegmayapti'
             ELSE 'Avtomatik ishlov'
           END AS owner,
           SUM(CASE
                 -- For a human stage only the queue portion counts here; the work portion is
                 -- reported separately below, because they are different problems.
                 WHEN s.STAGE_TYPE = 'HUMAN' AND e.PICKED_UP_AT IS NOT NULL
                   THEN (CAST(e.PICKED_UP_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24
                 WHEN s.STAGE_TYPE = 'HUMAN'
                   THEN 0
                 ELSE (CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24
               END) AS hrs
      FROM CREDIT_STAGE_EVENT e
      JOIN CREDIT_STAGE s ON s.STAGE_CODE = e.TO_STAGE
     GROUP BY CASE s.STAGE_TYPE
                WHEN 'CUSTOMER'  THEN 'Mijozni kutish'
                WHEN 'EXTERNAL'  THEN 'Tashqi tomon - baholash / notarius / davlat bazasi'
                WHEN 'COMMITTEE' THEN 'Qo''mita yig''ilishini kutish'
                WHEN 'HUMAN'     THEN 'Bank navbati - hech kim tegmayapti'
                ELSE 'Avtomatik ishlov'
              END
    UNION ALL
    SELECT 'Bank xodimi haqiqatan ishlayapti',
           SUM((CAST(e.COMPLETED_AT AS DATE) - CAST(e.PICKED_UP_AT AS DATE)) * 24)
      FROM CREDIT_STAGE_EVENT e
     WHERE e.PICKED_UP_AT IS NOT NULL)
 WHERE hrs > 0
 ORDER BY hrs DESC;
SPOOL OFF

-- Rework: the cost of sending an application round again.
SPOOL /tmp/credit_rework.csv
SELECT 'group_label,applications,median_days,p90_days' FROM dual;
SELECT g || ',' || COUNT(*) || ','
    || ROUND(MEDIAN(days), 2) || ','
    || ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY days), 2)
  FROM (
    SELECT a.APP_ID,
           CASE WHEN EXISTS (SELECT 1 FROM CREDIT_STAGE_EVENT r
                              WHERE r.APP_ID = a.APP_ID AND r.IS_REWORK = 1)
                THEN 'Documents returned at least once'
                ELSE 'Clean first pass' END AS g,
           (CAST(a.CLOSED_AT AS DATE) - CAST(a.SUBMITTED_AT AS DATE)) AS days
      FROM CREDIT_APPLICATION a
     WHERE a.CLOSED_AT IS NOT NULL)
 GROUP BY g
 ORDER BY g;
SPOOL OFF

-- Per-underwriter spread: is a slow stage a process problem or a staffing one?
SPOOL /tmp/credit_actors.csv
SELECT 'actor_role,actor_id,branch,cases,median_work_h,median_queue_h' FROM dual;
SELECT e.ACTOR_ROLE || ',' || e.ACTOR_ID || ',' || e.BRANCH_CODE || ',' || COUNT(*) || ','
    || ROUND(MEDIAN((CAST(e.COMPLETED_AT AS DATE) - CAST(e.PICKED_UP_AT AS DATE)) * 24), 3) || ','
    || ROUND(MEDIAN((CAST(e.PICKED_UP_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24), 3)
  FROM CREDIT_STAGE_EVENT e
 WHERE e.ACTOR_ID IS NOT NULL
 GROUP BY e.ACTOR_ROLE, e.ACTOR_ID, e.BRANCH_CODE
HAVING COUNT(*) >= 20
 ORDER BY e.ACTOR_ROLE, MEDIAN((CAST(e.COMPLETED_AT AS DATE) - CAST(e.PICKED_UP_AT AS DATE)) * 24) DESC;
SPOOL OFF

-- By product and collateral. Reporting one "average credit application" describes none of these
-- five populations: a microloan without collateral closes in 4.4 days and a corporate loan in
-- 15.1, and the dividing line is collateral rather than product type.
SPOOL /tmp/credit_by_product.csv
SELECT 'product,collateral,applications,median_days,p90_days,median_uw_queue_h,median_committee_h' FROM dual;
SELECT a.PRODUCT || ',' || (CASE WHEN a.HAS_COLLATERAL = 1 THEN 'ha' ELSE 'yoq' END) || ','
    || COUNT(DISTINCT a.APP_ID) || ','
    || ROUND(MEDIAN(CAST(a.CLOSED_AT AS DATE) - CAST(a.SUBMITTED_AT AS DATE)), 2) || ','
    || ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY
         CAST(a.CLOSED_AT AS DATE) - CAST(a.SUBMITTED_AT AS DATE)), 2) || ','
    || NVL(TO_CHAR(ROUND(MEDIAN(uw.q), 1)), '-') || ','
    || NVL(TO_CHAR(ROUND(MEDIAN(cm.h), 1)), '-')
  FROM CREDIT_APPLICATION a
  LEFT JOIN (SELECT APP_ID, (CAST(PICKED_UP_AT AS DATE) - CAST(ENTERED_AT AS DATE)) * 24 q
               FROM CREDIT_STAGE_EVENT WHERE TO_STAGE = 'ANDERRAYTER') uw ON uw.APP_ID = a.APP_ID
  LEFT JOIN (SELECT APP_ID, (CAST(COMPLETED_AT AS DATE) - CAST(ENTERED_AT AS DATE)) * 24 h
               FROM CREDIT_STAGE_EVENT WHERE TO_STAGE = 'QOMITA_KUTISH') cm ON cm.APP_ID = a.APP_ID
 WHERE a.CLOSED_AT IS NOT NULL
 GROUP BY a.PRODUCT, a.HAS_COLLATERAL
 ORDER BY MEDIAN(CAST(a.CLOSED_AT AS DATE) - CAST(a.SUBMITTED_AT AS DATE)) DESC;
SPOOL OFF

EXIT;

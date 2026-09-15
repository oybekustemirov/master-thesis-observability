-- Generates a credit-application event log with realistic stage timings.
--
-- Every distribution below is an ASSUMPTION, not a measurement, and each is stated in
-- docs/credit-process-observability.md so a reader can see exactly what was assumed and
-- substitute the bank's real figures. The point of the dataset is not to predict this bank's
-- durations; it is to exercise the analysis on a process whose stages differ in kind — automated,
-- human-queued, and customer-dependent — so the analysis can be shown to tell them apart.
--
-- NO PERSONAL DATA. Applicants are references of the form CUST-000000123; staff are an id, a
-- role and a branch. Nothing here identifies a person.

CREATE OR REPLACE PACKAGE PKG_CREDIT_PROCESS AS
  PROCEDURE seed_staff;
  PROCEDURE generate(p_applications IN NUMBER DEFAULT 5000,
                     p_days_span    IN NUMBER DEFAULT 90);
  PROCEDURE reset_all;
END PKG_CREDIT_PROCESS;
/

CREATE OR REPLACE PACKAGE BODY PKG_CREDIT_PROCESS AS

  -- Share of applications that never reach a decision, by exit point.
  PCT_REJECT_AT_SCORING  CONSTANT NUMBER := 18;
  PCT_REJECT_AT_UW       CONSTANT NUMBER := 9;
  PCT_WITHDRAWN          CONSTANT NUMBER := 6;
  -- Share whose documents come back incomplete and go round again. Rework is the classic
  -- process-mining finding: invisible in a stage average, and often the largest single cause of
  -- elapsed time.
  PCT_DOCS_REWORK        CONSTANT NUMBER := 22;

  FUNCTION pct RETURN NUMBER IS BEGIN RETURN DBMS_RANDOM.VALUE(0, 100); END;

  /**
   * Log-normal hours. Real process durations are right-skewed — most cases move quickly and a
   * long tail does not — and a normal distribution would understate exactly the tail that
   * operations teams care about.
   */
  FUNCTION lognormal_hours(p_median IN NUMBER, p_sigma IN NUMBER DEFAULT 0.8) RETURN NUMBER IS
    l_u1 NUMBER := GREATEST(DBMS_RANDOM.VALUE, 1e-10);
    l_u2 NUMBER := DBMS_RANDOM.VALUE;
    l_z  NUMBER := SQRT(-2 * LN(l_u1)) * COS(2 * 3.14159265358979 * l_u2);
  BEGIN
    RETURN p_median * EXP(p_sigma * l_z);
  END lognormal_hours;

  /**
   * Advances a timestamp by working hours, so a case entering a queue on Friday evening is not
   * credited with having waited over the weekend. Without this the queue-wait figures for HUMAN
   * stages are dominated by nights and weekends, and the analysis reports a staffing problem
   * where none exists.
   */
  FUNCTION add_working_hours(p_from IN TIMESTAMP, p_hours IN NUMBER) RETURN TIMESTAMP IS
    l_t      TIMESTAMP := p_from;
    l_left   NUMBER    := p_hours;
    l_hour   NUMBER;
    l_avail  NUMBER;
  BEGIN
    WHILE l_left > 0 LOOP
      l_hour := TO_NUMBER(TO_CHAR(l_t, 'HH24'))
              + TO_NUMBER(TO_CHAR(l_t, 'MI')) / 60;
      -- Weekend: jump to the next working morning. Matched on the English day name so the
      -- result does not depend on the session's NLS_TERRITORY.
      IF TO_CHAR(l_t, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT', 'SUN') THEN
        l_t := TRUNC(CAST(l_t AS DATE)) + 1 + 9 / 24;
        CONTINUE;
      END IF;
      IF l_hour < 9 THEN
        l_t := TRUNC(CAST(l_t AS DATE)) + 9 / 24;
        CONTINUE;
      END IF;
      IF l_hour >= 18 THEN
        l_t := TRUNC(CAST(l_t AS DATE)) + 1 + 9 / 24;
        CONTINUE;
      END IF;
      l_avail := 18 - l_hour;
      IF l_left <= l_avail THEN
        RETURN l_t + NUMTODSINTERVAL(l_left * 3600, 'SECOND');
      END IF;
      l_left := l_left - l_avail;
      l_t    := TRUNC(CAST(l_t AS DATE)) + 1 + 9 / 24;
    END LOOP;
    RETURN l_t;
  END add_working_hours;

  PROCEDURE seed_staff IS
    l_roles SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('DOC_OFFICER','UNDERWRITER','DISBURSEMENT');
    l_per   CONSTANT PLS_INTEGER := 6;
    l_n     PLS_INTEGER := 0;
  BEGIN
    DELETE FROM CREDIT_STAFF;
    FOR r IN 1 .. l_roles.COUNT LOOP
      FOR b IN 1 .. 5 LOOP
        FOR k IN 1 .. l_per LOOP
          l_n := l_n + 1;
          INSERT INTO CREDIT_STAFF (STAFF_ID, STAFF_ROLE, BRANCH_CODE, SPEED_FACTOR)
          VALUES ('STF-' || LPAD(l_n, 5, '0'),
                  l_roles(r),
                  'BR-' || LPAD(b, 3, '0'),
                  -- A real team is not uniform. 0.6 to 1.8 keeps the spread wide enough that
                  -- per-actor analysis has something to find.
                  ROUND(DBMS_RANDOM.VALUE(0.6, 1.8), 2));
        END LOOP;
      END LOOP;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('seeded ' || l_n || ' staff across 3 roles and 5 branches');
  END seed_staff;

  FUNCTION pick_staff(p_role IN VARCHAR2, p_branch IN VARCHAR2) RETURN CREDIT_STAFF%ROWTYPE IS
    l_row CREDIT_STAFF%ROWTYPE;
  BEGIN
    SELECT * INTO l_row FROM (
      SELECT * FROM CREDIT_STAFF
       WHERE STAFF_ROLE = p_role AND BRANCH_CODE = p_branch
       ORDER BY DBMS_RANDOM.VALUE)
     WHERE ROWNUM = 1;
    RETURN l_row;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    SELECT * INTO l_row FROM (
      SELECT * FROM CREDIT_STAFF WHERE STAFF_ROLE = p_role ORDER BY DBMS_RANDOM.VALUE)
     WHERE ROWNUM = 1;
    RETURN l_row;
  END pick_staff;

  PROCEDURE log_stage(p_app IN NUMBER, p_from IN VARCHAR2, p_to IN VARCHAR2,
                      p_entered IN TIMESTAMP, p_picked IN TIMESTAMP, p_done IN TIMESTAMP,
                      p_actor IN VARCHAR2, p_role IN VARCHAR2, p_branch IN VARCHAR2,
                      p_rework IN NUMBER DEFAULT 0) IS
  BEGIN
    INSERT INTO CREDIT_STAGE_EVENT
      (APP_ID, FROM_STAGE, TO_STAGE, ENTERED_AT, PICKED_UP_AT, COMPLETED_AT,
       ACTOR_ID, ACTOR_ROLE, BRANCH_CODE, IS_REWORK)
    VALUES (p_app, p_from, p_to, p_entered, p_picked, p_done,
            p_actor, p_role, p_branch, p_rework);
  END log_stage;

  PROCEDURE generate(p_applications IN NUMBER DEFAULT 5000,
                     p_days_span    IN NUMBER DEFAULT 90) IS
    l_app_id   NUMBER;
    l_now      TIMESTAMP := SYSTIMESTAMP;
    l_t        TIMESTAMP;
    l_entered  TIMESTAMP;
    l_picked   TIMESTAMP;
    l_stage    VARCHAR2(24);
    l_branch   VARCHAR2(8);
    l_product  VARCHAR2(16);
    l_channel  VARCHAR2(16);
    l_amount   NUMBER;
    l_staff    CREDIT_STAFF%ROWTYPE;
    l_roll     NUMBER;
    l_created  NUMBER := 0;
    l_rounds   PLS_INTEGER;
    l_from     VARCHAR2(24);
    l_outcome  VARCHAR2(16);
  BEGIN
    FOR i IN 1 .. p_applications LOOP
      l_branch  := 'BR-' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, 6)), 3, '0');
      l_product := CASE TRUNC(DBMS_RANDOM.VALUE(0, 4))
                     WHEN 0 THEN 'CONSUMER' WHEN 1 THEN 'AUTO'
                     WHEN 2 THEN 'MORTGAGE' ELSE 'SME' END;
      l_channel := CASE TRUNC(DBMS_RANDOM.VALUE(0, 4))
                     WHEN 0 THEN 'BRANCH' WHEN 1 THEN 'MOBILE'
                     WHEN 2 THEN 'WEB' ELSE 'AGENT' END;
      l_amount  := ROUND(EXP(DBMS_RANDOM.VALUE(15.5, 19.5)), 2);

      -- Submission somewhere in the window, during working hours.
      l_t := l_now - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, p_days_span) * 86400, 'SECOND');
      l_t := add_working_hours(l_t, 0);

      INSERT INTO CREDIT_APPLICATION
        (APP_REF, CUSTOMER_REF, PRODUCT, AMOUNT, CURRENCY, CHANNEL, BRANCH_CODE,
         CURRENT_STAGE, SUBMITTED_AT)
      VALUES ('APP-' || TO_CHAR(l_t, 'YYYYMMDD') || '-' || LPAD(i, 7, '0'),
              'CUST-' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, 20001)), 9, '0'),
              l_product, l_amount, 'UZS', l_channel, l_branch, 'SUBMITTED', l_t)
      RETURNING APP_ID INTO l_app_id;

      l_entered := l_t;
      l_t := l_t + NUMTODSINTERVAL(lognormal_hours(0.05, 0.5) * 3600, 'SECOND');
      log_stage(l_app_id, NULL, 'SUBMITTED', l_entered, NULL, l_t, NULL, 'SYSTEM', l_branch);

      -- ---- documents: the customer's time, and the loop that eats the calendar ----
      l_rounds := 1;
      l_from   := 'SUBMITTED';
      LOOP
        l_entered := l_t;
        l_t := l_t + NUMTODSINTERVAL(lognormal_hours(0.05, 0.5) * 3600, 'SECOND');
        log_stage(l_app_id, l_from, 'DOCS_REQUESTED', l_entered, NULL, l_t,
                  NULL, 'SYSTEM', l_branch, CASE WHEN l_rounds > 1 THEN 1 ELSE 0 END);

        -- The applicant is now the constraint. Calendar time, not working time: a customer
        -- uploading documents at midnight is normal and must not be pushed to Monday.
        l_entered := l_t;
        l_t := l_t + NUMTODSINTERVAL(lognormal_hours(26, 1.1) * 3600, 'SECOND');
        log_stage(l_app_id, 'DOCS_REQUESTED', 'DOCS_RECEIVED', l_entered, NULL, l_t,
                  NULL, 'CUSTOMER', l_branch, CASE WHEN l_rounds > 1 THEN 1 ELSE 0 END);

        -- Verification: a human, so it queues.
        l_staff   := pick_staff('DOC_OFFICER', l_branch);
        l_entered := l_t;
        l_picked  := add_working_hours(l_entered, lognormal_hours(3.5, 0.9));
        l_t       := l_picked + NUMTODSINTERVAL(
                       lognormal_hours(0.4, 0.6) / l_staff.SPEED_FACTOR * 3600, 'SECOND');
        log_stage(l_app_id, 'DOCS_RECEIVED', 'DOCS_VERIFIED', l_entered, l_picked, l_t,
                  l_staff.STAFF_ID, l_staff.STAFF_ROLE, l_branch,
                  CASE WHEN l_rounds > 1 THEN 1 ELSE 0 END);

        EXIT WHEN pct >= PCT_DOCS_REWORK OR l_rounds >= 3;
        l_rounds := l_rounds + 1;
        l_from   := 'DOCS_VERIFIED';
      END LOOP;

      -- ---- scoring: automated, and a common exit ----
      l_entered := l_t;
      l_t := l_t + NUMTODSINTERVAL(lognormal_hours(0.03, 0.4) * 3600, 'SECOND');
      log_stage(l_app_id, 'DOCS_VERIFIED', 'SCORING', l_entered, NULL, l_t, NULL, 'SYSTEM', l_branch);

      l_roll := pct;
      IF l_roll < PCT_REJECT_AT_SCORING THEN
        l_entered := l_t;
        l_t := l_t + NUMTODSINTERVAL(lognormal_hours(0.03, 0.4) * 3600, 'SECOND');
        log_stage(l_app_id, 'SCORING', 'REJECTED', l_entered, NULL, l_t, NULL, 'SYSTEM', l_branch);
        l_outcome := 'REJECTED'; l_stage := 'REJECTED';
        GOTO close_app;
      END IF;

      -- ---- underwriting: the expensive human stage ----
      l_staff   := pick_staff('UNDERWRITER', l_branch);
      l_entered := l_t;
      l_picked  := add_working_hours(l_entered, lognormal_hours(6.5, 1.0));
      l_t       := l_picked + NUMTODSINTERVAL(
                     lognormal_hours(1.1, 0.7) / l_staff.SPEED_FACTOR * 3600, 'SECOND');
      log_stage(l_app_id, 'SCORING', 'UNDERWRITING', l_entered, l_picked, l_t,
                l_staff.STAFF_ID, l_staff.STAFF_ROLE, l_branch);

      IF pct < PCT_REJECT_AT_UW THEN
        l_entered := l_t;
        l_t := l_t + NUMTODSINTERVAL(lognormal_hours(0.05, 0.4) * 3600, 'SECOND');
        log_stage(l_app_id, 'UNDERWRITING', 'REJECTED', l_entered, NULL, l_t, NULL, 'SYSTEM', l_branch);
        l_outcome := 'REJECTED'; l_stage := 'REJECTED';
        GOTO close_app;
      END IF;

      l_entered := l_t;
      l_t := l_t + NUMTODSINTERVAL(lognormal_hours(0.05, 0.4) * 3600, 'SECOND');
      log_stage(l_app_id, 'UNDERWRITING', 'DECISION', l_entered, NULL, l_t, NULL, 'SYSTEM', l_branch);

      -- ---- contract: the customer again ----
      IF pct < PCT_WITHDRAWN THEN
        l_entered := l_t;
        l_t := l_t + NUMTODSINTERVAL(lognormal_hours(40, 1.2) * 3600, 'SECOND');
        log_stage(l_app_id, 'DECISION', 'WITHDRAWN', l_entered, NULL, l_t, NULL, 'CUSTOMER', l_branch);
        l_outcome := 'WITHDRAWN'; l_stage := 'WITHDRAWN';
        GOTO close_app;
      END IF;

      l_entered := l_t;
      l_t := l_t + NUMTODSINTERVAL(lognormal_hours(34, 1.0) * 3600, 'SECOND');
      log_stage(l_app_id, 'DECISION', 'CONTRACT_SIGNED', l_entered, NULL, l_t,
                NULL, 'CUSTOMER', l_branch);

      -- ---- disbursement ----
      l_staff   := pick_staff('DISBURSEMENT', l_branch);
      l_entered := l_t;
      l_picked  := add_working_hours(l_entered, lognormal_hours(1.6, 0.8));
      l_t       := l_picked + NUMTODSINTERVAL(
                     lognormal_hours(0.3, 0.5) / l_staff.SPEED_FACTOR * 3600, 'SECOND');
      log_stage(l_app_id, 'CONTRACT_SIGNED', 'DISBURSED', l_entered, l_picked, l_t,
                l_staff.STAFF_ID, l_staff.STAFF_ROLE, l_branch);
      l_outcome := 'DISBURSED'; l_stage := 'DISBURSED';

      <<close_app>>
      UPDATE CREDIT_APPLICATION
         SET CURRENT_STAGE = l_stage, OUTCOME = l_outcome, CLOSED_AT = l_t
       WHERE APP_ID = l_app_id;

      l_created := l_created + 1;
      IF MOD(l_created, 500) = 0 THEN COMMIT; END IF;
    END LOOP;
    COMMIT;

    INSERT INTO CREDIT_SYNTH_CONFIG (APPLICATIONS, DAYS_SPAN, NOTES)
    VALUES (l_created, p_days_span,
            'lognormal stage durations; working-hours queues; ' || PCT_DOCS_REWORK
            || '% document rework; ' || PCT_REJECT_AT_SCORING || '% scoring reject; '
            || PCT_REJECT_AT_UW || '% underwriting reject; ' || PCT_WITHDRAWN || '% withdrawn');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('generated ' || l_created || ' credit applications over '
                      || p_days_span || ' days');
  END generate;

  PROCEDURE reset_all IS
  BEGIN
    DELETE FROM CREDIT_STAGE_EVENT;
    DELETE FROM CREDIT_APPLICATION;
    DELETE FROM CREDIT_SYNTH_CONFIG;
    COMMIT;
  END reset_all;

END PKG_CREDIT_PROCESS;
/

-- Generator for the Uzbek credit process.
--
-- Durations are calibrated to the ranges in the process description and remain ASSUMPTIONS.
-- Everything measurable about the analysis — that committee batching dominates, that the
-- underwriter's own work is a fraction of the underwriting stage — follows from the process
-- STRUCTURE, not from the exact parameters, which is why the structure is modelled carefully and
-- the parameters are declared openly.
--
-- NO PERSONAL DATA anywhere: applicants are CUST-000000123 references, staff an id and a role.

CREATE OR REPLACE PACKAGE PKG_CREDIT_PROCESS AS
  PROCEDURE seed_staff;
  PROCEDURE generate(p_applications IN NUMBER DEFAULT 5000,
                     p_days_span    IN NUMBER DEFAULT 120);
  PROCEDURE reset_all;
END PKG_CREDIT_PROCESS;
/

CREATE OR REPLACE PACKAGE BODY PKG_CREDIT_PROCESS AS

  -- Product mix. Microloans dominate by count; the collateralised products dominate elapsed time.
  PCT_MIKROQARZ CONSTANT NUMBER := 55;
  PCT_IPOTEKA   CONSTANT NUMBER := 18;
  PCT_BIZNES    CONSTANT NUMBER := 20;   -- remainder is KORPORATIV

  PCT_REJECT_EXTERNAL   CONSTANT NUMBER := 14;  -- KBI / MIB / tax check fails
  PCT_REJECT_UNDERWRITE CONSTANT NUMBER := 8;
  PCT_COMMITTEE_RETURN  CONSTANT NUMBER := 17;  -- returned for rework, documents insufficient
  PCT_WITHDRAWN         CONSTANT NUMBER := 5;
  PCT_DOCS_REWORK       CONSTANT NUMBER := 20;
  -- Share of external checks that stall on state-system maintenance or a data mismatch.
  PCT_EXTERNAL_STALL    CONSTANT NUMBER := 7;

  FUNCTION pct RETURN NUMBER IS BEGIN RETURN DBMS_RANDOM.VALUE(0, 100); END;

  FUNCTION lognormal_hours(p_median IN NUMBER, p_sigma IN NUMBER DEFAULT 0.8) RETURN NUMBER IS
    l_u1 NUMBER := GREATEST(DBMS_RANDOM.VALUE, 1e-10);
    l_u2 NUMBER := DBMS_RANDOM.VALUE;
  BEGIN
    RETURN p_median * EXP(p_sigma * SQRT(-2 * LN(l_u1)) * COS(2 * 3.14159265358979 * l_u2));
  END lognormal_hours;

  /** Advances by WORKING hours (Mon-Fri 09:00-18:00), so a queue entered on Friday evening is
      not charged for the weekend. */
  FUNCTION add_working_hours(p_from IN TIMESTAMP, p_hours IN NUMBER) RETURN TIMESTAMP IS
    l_t TIMESTAMP := p_from; l_left NUMBER := p_hours; l_hour NUMBER; l_avail NUMBER;
  BEGIN
    WHILE l_left > 0 LOOP
      l_hour := TO_NUMBER(TO_CHAR(l_t,'HH24')) + TO_NUMBER(TO_CHAR(l_t,'MI'))/60;
      IF TO_CHAR(l_t,'DY','NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT','SUN') THEN
        l_t := TRUNC(CAST(l_t AS DATE)) + 1 + 9/24; CONTINUE;
      END IF;
      IF l_hour < 9  THEN l_t := TRUNC(CAST(l_t AS DATE)) + 9/24;     CONTINUE; END IF;
      IF l_hour >= 18 THEN l_t := TRUNC(CAST(l_t AS DATE)) + 1 + 9/24; CONTINUE; END IF;
      l_avail := 18 - l_hour;
      IF l_left <= l_avail THEN RETURN l_t + NUMTODSINTERVAL(l_left*3600,'SECOND'); END IF;
      l_left := l_left - l_avail;
      l_t := TRUNC(CAST(l_t AS DATE)) + 1 + 9/24;
    END LOOP;
    RETURN l_t;
  END add_working_hours;

  /**
   * The next credit-committee sitting at or after p_from.
   *
   * This is the mechanic a queue model cannot express. An application finishing underwriting on
   * Tuesday at 14:30 has missed that day's sitting and waits until Thursday — not because anyone
   * is busy, but because the committee is not in the room. The wait is a property of the
   * calendar, and the only lever that shortens it is adding a sitting.
   */
  FUNCTION next_sitting(p_from IN TIMESTAMP) RETURN TIMESTAMP IS
    l_t     TIMESTAMP := p_from;
    l_hour  NUMBER;
    l_found NUMBER;
  BEGIN
    FOR i IN 0 .. 13 LOOP
      SELECT COUNT(*) INTO l_found FROM CREDIT_COMMITTEE_SCHEDULE
       WHERE DAY_OF_WEEK = TO_CHAR(l_t, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH');
      IF l_found > 0 THEN
        SELECT SITTING_HOUR INTO l_hour FROM CREDIT_COMMITTEE_SCHEDULE
         WHERE DAY_OF_WEEK = TO_CHAR(l_t, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH');
        IF i > 0 OR TO_NUMBER(TO_CHAR(l_t,'HH24')) + TO_NUMBER(TO_CHAR(l_t,'MI'))/60 <= l_hour THEN
          RETURN CAST(TRUNC(CAST(l_t AS DATE)) + l_hour/24 AS TIMESTAMP);
        END IF;
      END IF;
      l_t := CAST(TRUNC(CAST(l_t AS DATE)) + 1 AS TIMESTAMP);
    END LOOP;
    RETURN l_t;
  END next_sitting;

  PROCEDURE seed_staff IS
    l_roles SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
      'KREDIT_MUTAXASSISI','ANDERRAYTER','QOMITA_AZOSI','OPERATSION_XODIM');
    l_n PLS_INTEGER := 0;
  BEGIN
    DELETE FROM CREDIT_STAFF;
    FOR r IN 1 .. l_roles.COUNT LOOP
      FOR b IN 1 .. 5 LOOP
        FOR k IN 1 .. CASE l_roles(r) WHEN 'ANDERRAYTER' THEN 4 ELSE 5 END LOOP
          l_n := l_n + 1;
          INSERT INTO CREDIT_STAFF (STAFF_ID, STAFF_ROLE, BRANCH_CODE, SPEED_FACTOR)
          VALUES ('STF-' || LPAD(l_n,5,'0'), l_roles(r), 'BR-' || LPAD(b,3,'0'),
                  ROUND(DBMS_RANDOM.VALUE(0.6, 1.8), 2));
        END LOOP;
      END LOOP;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('seeded ' || l_n || ' staff');
  END seed_staff;

  FUNCTION pick_staff(p_role IN VARCHAR2, p_branch IN VARCHAR2) RETURN CREDIT_STAFF%ROWTYPE IS
    l_row CREDIT_STAFF%ROWTYPE;
  BEGIN
    SELECT * INTO l_row FROM (SELECT * FROM CREDIT_STAFF
       WHERE STAFF_ROLE = p_role AND BRANCH_CODE = p_branch ORDER BY DBMS_RANDOM.VALUE)
     WHERE ROWNUM = 1;
    RETURN l_row;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    SELECT * INTO l_row FROM (SELECT * FROM CREDIT_STAFF
       WHERE STAFF_ROLE = p_role ORDER BY DBMS_RANDOM.VALUE) WHERE ROWNUM = 1;
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
    VALUES (p_app, p_from, p_to, p_entered, p_picked, p_done, p_actor, p_role, p_branch, p_rework);
  END log_stage;

  PROCEDURE generate(p_applications IN NUMBER DEFAULT 5000,
                     p_days_span    IN NUMBER DEFAULT 120) IS
    l_app     NUMBER;
    l_now     TIMESTAMP := SYSTIMESTAMP;
    l_t       TIMESTAMP;
    l_ent     TIMESTAMP;
    l_pick    TIMESTAMP;
    l_branch  VARCHAR2(8);
    l_product VARCHAR2(16);
    l_channel VARCHAR2(16);
    l_amount  NUMBER;
    l_coll    NUMBER(1);
    l_staff   CREDIT_STAFF%ROWTYPE;
    l_stage   VARCHAR2(24);
    l_outcome VARCHAR2(16);
    l_from    VARCHAR2(24);
    l_rounds  PLS_INTEGER;
    l_passes  PLS_INTEGER;
    l_created NUMBER := 0;
    l_uw_med  NUMBER;
  BEGIN
    FOR i IN 1 .. p_applications LOOP
      l_branch  := 'BR-' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1,6)),3,'0');
      l_channel := CASE TRUNC(DBMS_RANDOM.VALUE(0,4)) WHEN 0 THEN 'FILIAL' WHEN 1 THEN 'MOBIL'
                     WHEN 2 THEN 'ONLAYN' ELSE 'AGENT' END;

      -- Product decides the path. A microloan without collateral skips valuation, the notary and
      -- often the committee; a corporate loan takes every stage. Mixing them into one "average
      -- credit application" is how a process report becomes useless to both.
      DECLARE l_r NUMBER := pct; BEGIN
        IF    l_r < PCT_MIKROQARZ                              THEN l_product := 'MIKROQARZ';
        ELSIF l_r < PCT_MIKROQARZ + PCT_IPOTEKA                THEN l_product := 'IPOTEKA';
        ELSIF l_r < PCT_MIKROQARZ + PCT_IPOTEKA + PCT_BIZNES   THEN l_product := 'BIZNES';
        ELSE                                                        l_product := 'KORPORATIV';
        END IF;
      END;
      l_coll := CASE l_product WHEN 'MIKROQARZ' THEN (CASE WHEN pct < 25 THEN 1 ELSE 0 END)
                  ELSE 1 END;
      l_amount := ROUND(CASE l_product
                    WHEN 'MIKROQARZ'  THEN EXP(DBMS_RANDOM.VALUE(15.4, 17.2))
                    WHEN 'IPOTEKA'    THEN EXP(DBMS_RANDOM.VALUE(19.0, 20.6))
                    WHEN 'BIZNES'     THEN EXP(DBMS_RANDOM.VALUE(18.4, 20.4))
                    ELSE                   EXP(DBMS_RANDOM.VALUE(20.0, 22.0)) END, 2);

      l_t := add_working_hours(
               l_now - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0, p_days_span) * 86400, 'SECOND'), 0);

      INSERT INTO CREDIT_APPLICATION
        (APP_REF, CUSTOMER_REF, PRODUCT, AMOUNT, CURRENCY, CHANNEL, BRANCH_CODE,
         CURRENT_STAGE, SUBMITTED_AT, HAS_COLLATERAL)
      VALUES ('APP-' || TO_CHAR(l_t,'YYYYMMDD') || '-' || LPAD(i,7,'0'),
              'CUST-' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1,20001)),9,'0'),
              l_product, l_amount, 'UZS', l_channel, l_branch, 'ARIZA_KIRITISH', l_t, l_coll)
      RETURNING APP_ID INTO l_app;

      -- 1. Ariza kiritish: a specialist enters it. 10-30 minutes when documents are ready.
      l_staff := pick_staff('KREDIT_MUTAXASSISI', l_branch);
      l_ent   := l_t;
      l_pick  := add_working_hours(l_ent, lognormal_hours(0.8, 0.7));
      l_t     := l_pick + NUMTODSINTERVAL(
                   lognormal_hours(0.33, 0.5) / l_staff.SPEED_FACTOR * 3600, 'SECOND');
      log_stage(l_app, NULL, 'ARIZA_KIRITISH', l_ent, l_pick, l_t,
                l_staff.STAFF_ID, l_staff.STAFF_ROLE, l_branch);

      -- 2-3. Documents from the customer, then the external checks. Documents can come back.
      l_rounds := 1;
      l_from   := 'ARIZA_KIRITISH';
      LOOP
        l_ent := l_t;
        l_t   := l_t + NUMTODSINTERVAL(lognormal_hours(20, 1.1) * 3600, 'SECOND');
        log_stage(l_app, l_from, 'HUJJAT_KUTISH', l_ent, NULL, l_t, NULL, 'CUSTOMER', l_branch,
                  CASE WHEN l_rounds > 1 THEN 1 ELSE 0 END);
        EXIT WHEN pct >= PCT_DOCS_REWORK OR l_rounds >= 3;
        l_rounds := l_rounds + 1;
        l_from   := 'HUJJAT_KUTISH';
      END LOOP;

      -- Automated in the normal case, minutes; occasionally blocked on a state system.
      l_ent := l_t;
      l_t   := l_t + NUMTODSINTERVAL(
                 CASE WHEN pct < PCT_EXTERNAL_STALL THEN lognormal_hours(9, 0.9)
                      ELSE lognormal_hours(0.08, 0.6) END * 3600, 'SECOND');
      log_stage(l_app, 'HUJJAT_KUTISH', 'TASHQI_TEKSHIRUV', l_ent, NULL, l_t,
                NULL, 'TASHQI_TIZIM', l_branch);

      IF pct < PCT_REJECT_EXTERNAL THEN
        l_ent := l_t; l_t := l_t + NUMTODSINTERVAL(lognormal_hours(0.05,0.4)*3600,'SECOND');
        log_stage(l_app,'TASHQI_TEKSHIRUV','RAD_ETILDI',l_ent,NULL,l_t,NULL,'SYSTEM',l_branch);
        l_outcome := 'RAD_ETILDI'; l_stage := 'RAD_ETILDI'; GOTO close_app;
      END IF;
      l_from := 'TASHQI_TEKSHIRUV';

      -- 4. Collateral valuation: a third party inspects the property. 1-3 working days.
      IF l_coll = 1 THEN
        l_ent := l_t;
        l_t   := add_working_hours(l_ent, lognormal_hours(17, 0.7));
        log_stage(l_app, l_from, 'GAROV_BAHOLASH', l_ent, NULL, l_t,
                  NULL, 'BAHOLASH_KOMPANIYASI', l_branch);
        l_from := 'GAROV_BAHOLASH';
      END IF;

      -- 5. Underwriting: 1-5 bank days for collateralised and large loans, much less for a
      --    microloan. The queue is separate from the work, and both are recorded.
      l_staff  := pick_staff('ANDERRAYTER', l_branch);
      l_uw_med := CASE l_product WHEN 'MIKROQARZ' THEN 1.2 WHEN 'IPOTEKA' THEN 6.0
                                 WHEN 'BIZNES' THEN 7.5 ELSE 11.0 END;
      l_ent  := l_t;
      l_pick := add_working_hours(l_ent, lognormal_hours(
                  CASE l_product WHEN 'MIKROQARZ' THEN 5 ELSE 14 END, 0.9));
      l_t    := l_pick + NUMTODSINTERVAL(
                  lognormal_hours(l_uw_med, 0.6) / l_staff.SPEED_FACTOR * 3600, 'SECOND');
      log_stage(l_app, l_from, 'ANDERRAYTER', l_ent, l_pick, l_t,
                l_staff.STAFF_ID, l_staff.STAFF_ROLE, l_branch);

      IF pct < PCT_REJECT_UNDERWRITE THEN
        l_ent := l_t; l_t := l_t + NUMTODSINTERVAL(lognormal_hours(0.1,0.4)*3600,'SECOND');
        log_stage(l_app,'ANDERRAYTER','RAD_ETILDI',l_ent,NULL,l_t,NULL,'SYSTEM',l_branch);
        l_outcome := 'RAD_ETILDI'; l_stage := 'RAD_ETILDI'; GOTO close_app;
      END IF;

      -- 6-7. The committee. Microloans without collateral are decided by a manager and skip it.
      IF l_coll = 1 OR l_product <> 'MIKROQARZ' THEN
        l_passes := 1;
        LOOP
          l_ent := l_t;
          l_t   := next_sitting(l_ent);         -- waiting for the room, not for a person
          log_stage(l_app, CASE WHEN l_passes = 1 THEN 'ANDERRAYTER' ELSE 'QAYTARILDI' END,
                    'QOMITA_KUTISH', l_ent, NULL, l_t, NULL, 'QOMITA', l_branch,
                    CASE WHEN l_passes > 1 THEN 1 ELSE 0 END);

          l_staff := pick_staff('QOMITA_AZOSI', l_branch);
          l_ent   := l_t;
          l_t     := l_ent + NUMTODSINTERVAL(lognormal_hours(0.4, 0.5) * 3600, 'SECOND');
          log_stage(l_app, 'QOMITA_KUTISH', 'QOMITA_QARORI', l_ent, l_ent, l_t,
                    l_staff.STAFF_ID, l_staff.STAFF_ROLE, l_branch,
                    CASE WHEN l_passes > 1 THEN 1 ELSE 0 END);

          EXIT WHEN pct >= PCT_COMMITTEE_RETURN OR l_passes >= 3;
          -- Returned: documents insufficient. The case goes back and waits for the next sitting.
          --
          -- A credit specialist has to redo the file, so this stage carries BOTH a pickup and an
          -- actor. Emitted without them at first, and that single omission had two consequences.
          -- The rework a specialist performs became unattributable - invisible in any per-employee
          -- report, while rework touches 27 % of applications. And because the classifier treats a
          -- HUMAN stage with no pickup as work from end to end, the whole interval counted as
          -- staff working time: 13 378 hours of queue reported as effort, against 21 728 hours of
          -- real work. The share of elapsed time a bank employee spends working was overstated by
          -- more than half.
          l_staff := pick_staff('KREDIT_MUTAXASSISI', l_branch);
          l_ent := l_t;
          l_t   := add_working_hours(l_ent, lognormal_hours(6, 0.9));
          log_stage(l_app, 'QOMITA_QARORI', 'QAYTARILDI', l_ent,
                    l_t - NUMTODSINTERVAL(LEAST(lognormal_hours(0.75, 0.7),
                                                6 * 0.9) * 3600, 'SECOND'),
                    l_t, l_staff.STAFF_ID, l_staff.STAFF_ROLE, l_branch, 1);
          l_passes := l_passes + 1;
        END LOOP;
        l_from := 'QOMITA_QARORI';
      ELSE
        l_from := 'ANDERRAYTER';
      END IF;

      -- 8. Insurance and the notarial encumbrance, when there is collateral. One working day.
      IF l_coll = 1 THEN
        l_ent := l_t;
        l_t   := add_working_hours(l_ent, lognormal_hours(7, 0.6));
        log_stage(l_app, l_from, 'SUGURTA_NOTARIUS', l_ent, NULL, l_t,
                  NULL, 'SUGURTA_NOTARIUS', l_branch);
        l_from := 'SUGURTA_NOTARIUS';
      END IF;

      -- 9. Contract and guarantors: the customer again.
      IF pct < PCT_WITHDRAWN THEN
        l_ent := l_t; l_t := l_t + NUMTODSINTERVAL(lognormal_hours(30,1.1)*3600,'SECOND');
        log_stage(l_app, l_from, 'BEKOR_QILINDI', l_ent, NULL, l_t, NULL, 'CUSTOMER', l_branch);
        l_outcome := 'BEKOR_QILINDI'; l_stage := 'BEKOR_QILINDI'; GOTO close_app;
      END IF;
      l_ent := l_t;
      l_t   := l_t + NUMTODSINTERVAL(lognormal_hours(9, 0.9) * 3600, 'SECOND');
      log_stage(l_app, l_from, 'SHARTNOMA', l_ent, NULL, l_t, NULL, 'CUSTOMER', l_branch);

      -- 10. Disbursement.
      l_staff := pick_staff('OPERATSION_XODIM', l_branch);
      l_ent   := l_t;
      l_pick  := add_working_hours(l_ent, lognormal_hours(2.5, 0.8));
      l_t     := l_pick + NUMTODSINTERVAL(
                   lognormal_hours(0.5, 0.5) / l_staff.SPEED_FACTOR * 3600, 'SECOND');
      log_stage(l_app, 'SHARTNOMA', 'AJRATISH', l_ent, l_pick, l_t,
                l_staff.STAFF_ID, l_staff.STAFF_ROLE, l_branch);
      l_outcome := 'AJRATILDI'; l_stage := 'AJRATISH';

      <<close_app>>
      UPDATE CREDIT_APPLICATION SET CURRENT_STAGE = l_stage, OUTCOME = l_outcome, CLOSED_AT = l_t
       WHERE APP_ID = l_app;

      l_created := l_created + 1;
      IF MOD(l_created, 500) = 0 THEN COMMIT; END IF;
    END LOOP;
    COMMIT;

    INSERT INTO CREDIT_SYNTH_CONFIG (APPLICATIONS, DAYS_SPAN, NOTES)
    VALUES (l_created, p_days_span,
            'UZ credit process; committee sits TUE+THU 14:00; ' || PCT_COMMITTEE_RETURN
            || '% committee returns; ' || PCT_DOCS_REWORK || '% document rework; '
            || PCT_EXTERNAL_STALL || '% external-system stall; collateral drives the path');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('generated ' || l_created || ' applications');
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

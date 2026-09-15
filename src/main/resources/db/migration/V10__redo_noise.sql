-- Instrument for experiment C2 (docs/experiment-c2-design.md).
--
-- Generates a controlled, sustained volume of redo in a table that is deliberately NOT in any
-- connector's table.include.list, so that "total redo" can be varied independently of "captured
-- writes". Without that independence C2 cannot be tested at all: every naive version of this
-- experiment changes both quantities at once and can only measure their sum.
--
-- Held as .pending until the main matrix finishes. Introducing a migration mid-matrix would
-- apply it between cells and change the database underneath a comparison that assumes it
-- constant — the same class of contamination this thesis spends its methodology avoiding.

CREATE TABLE REDO_NOISE (
  ID         NUMBER(10)     PRIMARY KEY,
  PAD1       VARCHAR2(400)  NOT NULL,
  PAD2       VARCHAR2(400)  NOT NULL,
  TOUCHED    NUMBER(12)     DEFAULT 0 NOT NULL,
  UPDATED_AT TIMESTAMP(6)   DEFAULT SYSTIMESTAMP NOT NULL
);

CREATE OR REPLACE PACKAGE PKG_REDO_NOISE AS
  -- Populates the fixed row pool. Called once; the pool is reference data and survives
  -- reset_workload between runs.
  PROCEDURE seed(p_rows IN PLS_INTEGER DEFAULT 50000);

  -- Holds a steady update rate for p_seconds. Rate is expressed in updates per second because
  -- redo per update is near-constant for this row shape; the calibration run in the C2 design
  -- converts the level into bytes per second on the instance actually being measured.
  PROCEDURE run(p_seconds IN PLS_INTEGER, p_updates_per_second IN PLS_INTEGER);

  -- Redo bytes attributable to one update of this table, measured rather than assumed.
  FUNCTION calibrate(p_updates IN PLS_INTEGER DEFAULT 20000) RETURN NUMBER;
END PKG_REDO_NOISE;
/

CREATE OR REPLACE PACKAGE BODY PKG_REDO_NOISE AS

  g_pool PLS_INTEGER;

  FUNCTION pool_size RETURN PLS_INTEGER IS
  BEGIN
    IF g_pool IS NULL THEN
      SELECT COUNT(*) INTO g_pool FROM REDO_NOISE;
    END IF;
    RETURN GREATEST(g_pool, 1);
  END pool_size;

  PROCEDURE seed(p_rows IN PLS_INTEGER DEFAULT 50000) IS
  BEGIN
    DELETE FROM REDO_NOISE;
    INSERT /*+ APPEND */ INTO REDO_NOISE (ID, PAD1, PAD2)
    SELECT LEVEL,
           RPAD('N' || LEVEL, 400, 'x'),
           RPAD('M' || LEVEL, 400, 'y')
      FROM dual CONNECT BY LEVEL <= p_rows;
    COMMIT;
    g_pool := p_rows;
    DBMS_OUTPUT.PUT_LINE('REDO_NOISE seeded with ' || p_rows || ' rows');
  END seed;

  /**
   * One second of work, then sleep the remainder of that second.
   *
   * Paced rather than bursty on purpose. A single large batch produces a redo SPIKE and a log
   * switch storm instead of a sustained LEVEL, and Debezium's adaptive batch sizing would then
   * be responding to a transient rather than to the condition under test.
   *
   * Updates rather than inserts, against a fixed pool, so the table does not grow across 36
   * runs and every run starts from the same physical size. A growing table would make later
   * runs differ from earlier ones in a way that has nothing to do with the manipulation.
   */
  PROCEDURE run(p_seconds IN PLS_INTEGER, p_updates_per_second IN PLS_INTEGER) IS
    l_deadline  TIMESTAMP := SYSTIMESTAMP + NUMTODSINTERVAL(p_seconds, 'SECOND');
    l_batch     CONSTANT PLS_INTEGER := 500;
    l_pool      CONSTANT PLS_INTEGER := pool_size;
    l_done      PLS_INTEGER;
    l_start     TIMESTAMP;
    l_elapsed   NUMBER;
    l_total     NUMBER := 0;
  BEGIN
    -- Tagged so a leftover generator can be found and killed between cells by module name.
    -- A noise session that outlived its cell would add uncaptured redo to the NEXT cell, and
    -- since the levels are the independent variable that is the one contamination this
    -- experiment cannot tolerate.
    DBMS_APPLICATION_INFO.SET_MODULE('C2_NOISE', TO_CHAR(p_updates_per_second));

    IF p_updates_per_second <= 0 THEN
      -- Level N0: the control. The procedure is still called so that its session, its parse
      -- and its scheduling overhead are present in every condition alike.
      DBMS_SESSION.SLEEP(p_seconds);
      RETURN;
    END IF;

    WHILE SYSTIMESTAMP < l_deadline LOOP
      l_start := SYSTIMESTAMP;
      l_done  := 0;
      WHILE l_done < p_updates_per_second LOOP
        UPDATE REDO_NOISE
           SET PAD1       = RPAD(TO_CHAR(SYSTIMESTAMP, 'SSSSSFF6'), 400, 'z'),
               TOUCHED    = TOUCHED + 1,
               UPDATED_AT = SYSTIMESTAMP
         WHERE ID BETWEEN MOD(l_done * 7919 + l_total, l_pool) + 1
                      AND MOD(l_done * 7919 + l_total, l_pool) + LEAST(l_batch, p_updates_per_second - l_done);
        l_done := l_done + LEAST(l_batch, p_updates_per_second - l_done);
        COMMIT;
      END LOOP;
      l_total := l_total + l_done;

      l_elapsed := EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start));
      IF l_elapsed < 1 THEN
        DBMS_SESSION.SLEEP(1 - l_elapsed);
      END IF;
      -- Falling behind is a RESULT, not something to hide: it means the requested level exceeds
      -- what the instance can sustain, and that level must be excluded from the fit.
    END LOOP;
    DBMS_APPLICATION_INFO.SET_MODULE(NULL, NULL);
    DBMS_OUTPUT.PUT_LINE('REDO_NOISE updates issued: ' || l_total);
  END run;

  /**
   * Redo bytes per update, measured on the instance that will actually be used rather than
   * taken from the row width. The C2 design expresses its noise levels in redo bytes per
   * second, so this conversion has to be an observation, not an estimate.
   */
  FUNCTION calibrate(p_updates IN PLS_INTEGER DEFAULT 20000) RETURN NUMBER IS
    l_before NUMBER;
    l_after  NUMBER;
    l_pool   CONSTANT PLS_INTEGER := pool_size;
    l_done   PLS_INTEGER := 0;
  BEGIN
    SELECT s.value INTO l_before FROM v$mystat s JOIN v$statname n
      ON n.statistic# = s.statistic# WHERE n.name = 'redo size';
    WHILE l_done < p_updates LOOP
      UPDATE REDO_NOISE
         SET PAD1 = RPAD(TO_CHAR(SYSTIMESTAMP, 'SSSSSFF6'), 400, 'z'),
             TOUCHED = TOUCHED + 1, UPDATED_AT = SYSTIMESTAMP
       WHERE ID BETWEEN MOD(l_done, l_pool) + 1 AND MOD(l_done, l_pool) + 500;
      l_done := l_done + 500;
      COMMIT;
    END LOOP;
    SELECT s.value INTO l_after FROM v$mystat s JOIN v$statname n
      ON n.statistic# = s.statistic# WHERE n.name = 'redo size';
    RETURN (l_after - l_before) / p_updates;
  END calibrate;

END PKG_REDO_NOISE;
/

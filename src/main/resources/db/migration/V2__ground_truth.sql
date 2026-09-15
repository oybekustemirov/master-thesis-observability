-- ============================================================================
-- THE CONTROL INSTRUMENT
-- ============================================================================
-- GROUND_TRUTH records every committed A1 state transition, written by a trigger in
-- the SAME transaction as the business change. It is the independent reference against
-- which every pipeline's loss rate (LR) is computed.
--
-- EXPERIMENT DESIGN NOTE — why a trigger, and how the resulting bias is handled:
--
--   A trigger is the only mechanism that captures ALL writers, including PL/SQL batch
--   and direct SQL, which is required for the reference to be independent of the
--   application-level pipelines under test. Using the application to write ground truth
--   would make the reference circular for the WRAPPER modes and blind for batch writers.
--
--   The cost is that ground truth adds constant overhead to every instrumented run.
--   That bias is handled by measuring THREE baselines rather than one:
--
--     OFF          — no ground truth, no events. True zero-instrumentation throughput.
--     BASELINE_GT  — ground truth trigger only. The cost of the measuring apparatus.
--     <mode>       — ground truth trigger + that mode's mechanism.
--
--   The reported cost of a mode is (<mode> - BASELINE_GT); the cost of the apparatus
--   itself is (BASELINE_GT - OFF) and is reported separately rather than hidden.
--   This makes the instrument's own overhead an explicit, quantified result.
-- ============================================================================

CREATE TABLE GROUND_TRUTH (
  TXN_ID      NUMBER(19)   NOT NULL,
  EVENT_SEQ   NUMBER(10)   NOT NULL,
  OLD_STATUS  VARCHAR2(16),
  NEW_STATUS  VARCHAR2(16) NOT NULL,
  SOURCE_OP   VARCHAR2(16) NOT NULL,
  COMMIT_TS   TIMESTAMP(6) DEFAULT SYSTIMESTAMP NOT NULL,
  COMMIT_SCN  NUMBER,
  CONSTRAINT PK_GROUND_TRUTH PRIMARY KEY (TXN_ID, EVENT_SEQ)
);

-- Per-aggregate monotonic counter, shared by ground truth and by every pipeline, so
-- that gap detection and ordering-violation rate are computed on the same key space.
CREATE TABLE TXN_A1_EVT_SEQ (
  TXN_ID   NUMBER(19) PRIMARY KEY,
  LAST_SEQ NUMBER(10) DEFAULT 0 NOT NULL
);

CREATE OR REPLACE FUNCTION NEXT_EVT_SEQ(p_txn_id IN NUMBER) RETURN NUMBER IS
  l_seq NUMBER;
BEGIN
  MERGE INTO TXN_A1_EVT_SEQ t
  USING (SELECT p_txn_id AS txn_id FROM dual) s ON (t.txn_id = s.txn_id)
   WHEN MATCHED     THEN UPDATE SET t.last_seq = t.last_seq + 1
   WHEN NOT MATCHED THEN INSERT (txn_id, last_seq) VALUES (p_txn_id, 1);
  SELECT last_seq INTO l_seq FROM TXN_A1_EVT_SEQ WHERE txn_id = p_txn_id;
  RETURN l_seq;
END;
/

CREATE OR REPLACE TRIGGER TRG_GROUND_TRUTH
FOR INSERT OR UPDATE OF STATUS ON TXN_A1
COMPOUND TRIGGER
  TYPE t_chg IS RECORD (txn_id NUMBER, old_status VARCHAR2(16), new_status VARCHAR2(16));
  TYPE t_buf IS TABLE OF t_chg INDEX BY PLS_INTEGER;
  g_buf t_buf;

  AFTER EACH ROW IS
  BEGIN
    IF INSERTING OR :NEW.STATUS <> :OLD.STATUS THEN
      g_buf(g_buf.COUNT + 1).txn_id := :NEW.TXN_ID;
      g_buf(g_buf.COUNT).old_status := CASE WHEN UPDATING THEN :OLD.STATUS END;
      g_buf(g_buf.COUNT).new_status := :NEW.STATUS;
    END IF;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
    -- OBSV holds SELECT on V_$DATABASE but not EXECUTE on DBMS_FLASHBACK, and the SCN is
    -- read ONCE per statement rather than once per row to keep the control instrument's
    -- own overhead as low as possible.
    l_scn NUMBER;
  BEGIN
    -- PLS-00678: RETURN is not permitted inside a compound trigger section, so an
    -- early exit must be expressed as a guarding IF rather than a guard clause.
    IF g_buf.COUNT > 0 THEN
      SELECT current_scn INTO l_scn FROM v$database;
      FOR i IN 1 .. g_buf.COUNT LOOP
      INSERT INTO GROUND_TRUTH (TXN_ID, EVENT_SEQ, OLD_STATUS, NEW_STATUS, SOURCE_OP, COMMIT_SCN)
      VALUES (g_buf(i).txn_id, NEXT_EVT_SEQ(g_buf(i).txn_id),
              g_buf(i).old_status, g_buf(i).new_status,
              CASE WHEN g_buf(i).old_status IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
              l_scn);
      END LOOP;
    END IF;
    g_buf.DELETE;
  END AFTER STATEMENT;
END;
/

-- Disabled by default: the harness enables it for every mode except OFF.
ALTER TRIGGER TRG_GROUND_TRUTH DISABLE;

-- Debezium heartbeat target. Without a heartbeat the committed offset stalls during idle
-- periods, which is the precondition for the archive-purge loss mode (fault F4).
CREATE TABLE DBZ_HEARTBEAT (ID NUMBER(1) PRIMARY KEY, TS TIMESTAMP(6));
INSERT INTO DBZ_HEARTBEAT VALUES (1, SYSTIMESTAMP);

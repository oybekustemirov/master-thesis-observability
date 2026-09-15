-- Dumps the control instrument for offline reconciliation.
-- Format: txn_id,event_seq,new_status,commit_epoch_ms
SET LINESIZE 200 PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TRIMSPOOL ON TERMOUT OFF
ALTER SESSION SET CONTAINER = OBSVPDB;
-- Connected as SYS, so the current schema is SYS. Without this the unqualified table name
-- resolves to nothing and the spool silently produces an error page instead of data —
-- which the analysis would then score as 100% phantom events.
ALTER SESSION SET CURRENT_SCHEMA = OBSV;
SPOOL /tmp/ground_truth.csv
SELECT txn_id || ',' || event_seq || ',' || new_status || ',' ||
       TO_CHAR(ROUND((CAST(commit_ts AS DATE) - DATE '1970-01-01') * 86400000
               + TO_NUMBER(TO_CHAR(commit_ts, 'FF3'))))
  FROM GROUND_TRUTH
 ORDER BY txn_id, event_seq;
SPOOL OFF
EXIT;

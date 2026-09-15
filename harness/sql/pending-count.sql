-- Two numbers, tab-separated: in-database backlog for the active mode, and the committed
-- transition count.
--
-- The second one is what makes the drain check correct. Waiting for the sink to stop GROWING is
-- a proxy, and a bad one for the Debezium modes: their mining cycle has gaps of several seconds,
-- so a sink can sit still for three polls while the connector is only a third of the way through
-- a backlog. That produced HYBRID/F11B/r1 reporting 71.9 % loss where its two sibling runs
-- reported 0. Comparing the sink against the number of transitions actually committed tests
-- completeness directly instead of guessing at it from stillness.
SET FEEDBACK OFF VERIFY OFF DEFINE ON PAGESIZE 0 HEADING OFF TRIMSPOOL ON
WHENEVER SQLERROR EXIT 1
ALTER SESSION SET CONTAINER = OBSVPDB;
ALTER SESSION SET CURRENT_SCHEMA = OBSV;

SPOOL /tmp/pending.txt
SELECT CASE UPPER('&1')
         WHEN 'AQ'         THEN (SELECT COUNT(*) FROM OBSV."AQ$A1_EVT_QT"
                                  WHERE MSG_STATE IN ('READY', 'WAIT'))
         WHEN 'WRAPPER_B3' THEN (SELECT COUNT(*) FROM OBSV.A1_EVENT_OUTBOX
                                  WHERE PUBLISHED_AT IS NULL)
         ELSE 0
       END
       || ' ' || (SELECT COUNT(*) FROM OBSV.GROUND_TRUTH)
  FROM dual;
SPOOL OFF
EXIT;

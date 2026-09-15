-- Database counters for the performance metrics. Taken before and after a run; the deltas
-- give redo amplification, commit count and CPU consumption attributable to the run.
SET LINESIZE 200 PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF TRIMSPOOL ON TERMOUT OFF
SPOOL /tmp/db_stats.csv
SELECT n.name || ',' || s.value
  FROM v$sysstat s JOIN v$statname n ON n.statistic# = s.statistic#
 WHERE n.name IN ('redo size','redo entries','user commits','user rollbacks',
                  'db block changes','execute count','CPU used by this session',
                  'session logical reads','physical writes','DB time');
SELECT 'wait_' || REPLACE(event, ' ', '_') || ',' || time_waited_micro
  FROM v$system_event
 WHERE event IN ('log file sync','log file parallel write','db file sequential read',
                 'enq: TX - row lock contention','buffer busy waits',
                 'Streams AQ: enqueue blocked on low memory');
SPOOL OFF
EXIT;

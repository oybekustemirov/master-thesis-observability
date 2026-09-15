-- Measures redo bytes per noise update on THIS instance and writes it to /tmp/noise_cal.txt.
--
-- The function performs DML, so it CANNOT be called from a query: "SELECT calibrate(...) FROM
-- dual" raises ORA-14551. The call therefore happens in a PL/SQL block and the query only
-- formats the resulting bind variable.
SET FEEDBACK OFF VERIFY OFF PAGESIZE 0 HEADING OFF TRIMSPOOL ON
WHENEVER SQLERROR EXIT 1
VARIABLE b NUMBER
BEGIN
  :b := PKG_REDO_NOISE.calibrate(20000);
END;
/
SPOOL /tmp/noise_cal.txt
SELECT TO_CHAR(:b, 'FM999999990.00') FROM dual;
SPOOL OFF
EXIT;

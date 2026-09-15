-- Drives the C2 noise generator. &1 = seconds, &2 = updates per second.
SET FEEDBACK OFF VERIFY OFF SERVEROUTPUT ON
WHENEVER SQLERROR EXIT 1
BEGIN PKG_REDO_NOISE.run(TO_NUMBER('&1'), TO_NUMBER('&2')); END;
/
EXIT;

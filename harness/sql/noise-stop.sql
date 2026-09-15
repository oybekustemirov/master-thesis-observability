-- Kills any noise generator still running, identified by the module it tags itself with.
-- Run between cells: a generator that outlives its cell contaminates the next one's
-- independent variable.
SET FEEDBACK OFF VERIFY OFF SERVEROUTPUT ON
ALTER SESSION SET CONTAINER = OBSVPDB;
SET SERVEROUTPUT ON
DECLARE
  l_killed PLS_INTEGER := 0;
BEGIN
  FOR s IN (SELECT sid, serial# FROM v$session WHERE module = 'C2_NOISE') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
      l_killed := l_killed + 1;
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('could not kill ' || s.sid || ': ' || SQLERRM);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('noise sessions killed: ' || l_killed);
END;
/
EXIT;

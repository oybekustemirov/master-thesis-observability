-- Application schema owner inside the PDB. Tables are created by Flyway
-- (src/main/resources/db/migration) so schema evolution lives with the application.
--
-- SQL*Plus PITFALLS avoided in this file, both of which fail SILENTLY under
-- WHENEVER SQLERROR CONTINUE and cost real debugging time:
--   1. A trailing "-- comment" on the SAME line as the ";" terminator raises ORA-03405
--      and swallows the statements that follow.
--   2. A line ending in "-" is a SQL*Plus continuation character, so a PROMPT ending in
--      "---" consumes the next line as part of the prompt.
-- Every comment here is therefore on its own line, and no line ends with a hyphen.
SET ECHO OFF FEEDBACK ON VERIFY OFF
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER = OBSVPDB;
-- SERVEROUTPUT must be re-enabled AFTER the container switch: switching container
-- resets session state, silently discarding all later DBMS_OUTPUT.
SET SERVEROUTPUT ON

DECLARE
  v_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM dba_users WHERE username = 'OBSV';
  IF v_cnt = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER obsv IDENTIFIED BY "Obsv_2026" '
                   || 'DEFAULT TABLESPACE users QUOTA UNLIMITED ON users';
    DBMS_OUTPUT.PUT_LINE('created obsv');
  ELSE
    DBMS_OUTPUT.PUT_LINE('obsv present');
  END IF;
END;
/

GRANT CREATE SESSION      TO obsv;
GRANT CREATE TABLE        TO obsv;
GRANT CREATE SEQUENCE     TO obsv;
GRANT CREATE PROCEDURE    TO obsv;
GRANT CREATE TRIGGER      TO obsv;
GRANT CREATE VIEW         TO obsv;
GRANT CREATE TYPE         TO obsv;
GRANT CREATE JOB          TO obsv;

-- CURRENT_SCN for end-to-end latency instrumentation
GRANT SELECT ON V_$DATABASE     TO obsv;
-- redo size and user commits, for the redo-amplification metric
GRANT SELECT ON V_$SYSSTAT      TO obsv;
GRANT SELECT ON V_$STATNAME     TO obsv;
GRANT SELECT ON V_$SYSTEM_EVENT TO obsv;
-- long-running transaction detection, precondition for fault case F5
GRANT SELECT ON V_$TRANSACTION  TO obsv;

-- Approach 1 (Advanced Queuing)
GRANT EXECUTE ON DBMS_AQ    TO obsv;
GRANT EXECUTE ON DBMS_AQADM TO obsv;
GRANT AQ_ADMINISTRATOR_ROLE TO obsv;
GRANT AQ_USER_ROLE          TO obsv;
GRANT EXECUTE ON SYS.AQ$_JMS_TEXT_MESSAGE TO obsv;
-- controlled sleeps for fault injection
GRANT EXECUTE ON DBMS_LOCK  TO obsv;

-- Fail loudly rather than reporting a false success.
DECLARE
  v_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM dba_tab_privs
   WHERE grantee = 'OBSV' AND table_name = 'DBMS_AQADM';
  IF v_cnt = 0 THEN
    RAISE_APPLICATION_ERROR(-20002, 'DBMS_AQADM grant MISSING - Approach 1 unavailable');
  END IF;
  DBMS_OUTPUT.PUT_LINE('>>> obsv schema owner ready');
END;
/
EXIT;

-- The C2 noise generator calibrates itself by reading its own session's redo counter, so the
-- schema owner needs these dynamic views. Granted here as SYS because a Flyway migration runs
-- as OBSV and cannot grant itself a SYS-owned object privilege.
GRANT SELECT ON V_$MYSTAT   TO OBSV;
GRANT SELECT ON V_$STATNAME TO OBSV;
GRANT SELECT ON V_$SYSSTAT  TO OBSV;

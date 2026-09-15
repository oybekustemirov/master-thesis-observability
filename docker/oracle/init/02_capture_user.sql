-- Debezium capture user, equivalent to the grants in the Debezium Oracle documentation.
-- Idempotent: re-running is safe.
--
-- IMPLEMENTATION NOTE: container switching is done at SQL*Plus level, never inside a
-- PL/SQL block. "ALTER SESSION SET CONTAINER" is not permitted from PL/SQL — attempting
-- it via EXECUTE IMMEDIATE fails, and under WHENEVER SQLERROR CONTINUE it fails SILENTLY,
-- leaving the capture user absent while the script still reports success.
SET ECHO OFF FEEDBACK ON LINESIZE 200 SERVEROUTPUT ON VERIFY OFF
WHENEVER SQLERROR CONTINUE

-- A common user's default tablespace must exist in EVERY container, not only CDB$ROOT,
-- or CREATE USER ... CONTAINER=ALL fails with ORA-65048 / ORA-00959 naming the first PDB
-- that lacks it. The same applies to a production bank CDB.

ALTER SESSION SET CONTAINER = CDB$ROOT;
ALTER SYSTEM SET DB_CREATE_FILE_DEST='/opt/oracle/oradata' SCOPE=BOTH;
DECLARE
  v_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM dba_tablespaces WHERE tablespace_name = 'LOGMINER_TBS';
  IF v_cnt = 0 THEN
    EXECUTE IMMEDIATE 'CREATE TABLESPACE logminer_tbs DATAFILE SIZE 100M AUTOEXTEND ON MAXSIZE 4G';
    DBMS_OUTPUT.PUT_LINE('created logminer_tbs in ' || SYS_CONTEXT('USERENV','CON_NAME'));
  ELSE
    DBMS_OUTPUT.PUT_LINE('logminer_tbs present in ' || SYS_CONTEXT('USERENV','CON_NAME'));
  END IF;
END;
/

ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON
ALTER SYSTEM SET DB_CREATE_FILE_DEST='/opt/oracle/oradata' SCOPE=BOTH;
DECLARE
  v_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM dba_tablespaces WHERE tablespace_name = 'LOGMINER_TBS';
  IF v_cnt = 0 THEN
    EXECUTE IMMEDIATE 'CREATE TABLESPACE logminer_tbs DATAFILE SIZE 100M AUTOEXTEND ON MAXSIZE 4G';
    DBMS_OUTPUT.PUT_LINE('created logminer_tbs in ' || SYS_CONTEXT('USERENV','CON_NAME'));
  ELSE
    DBMS_OUTPUT.PUT_LINE('logminer_tbs present in ' || SYS_CONTEXT('USERENV','CON_NAME'));
  END IF;
END;
/

ALTER SESSION SET CONTAINER = OBSVPDB;
SET SERVEROUTPUT ON
ALTER SYSTEM SET DB_CREATE_FILE_DEST='/opt/oracle/oradata' SCOPE=BOTH;
DECLARE
  v_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM dba_tablespaces WHERE tablespace_name = 'LOGMINER_TBS';
  IF v_cnt = 0 THEN
    EXECUTE IMMEDIATE 'CREATE TABLESPACE logminer_tbs DATAFILE SIZE 100M AUTOEXTEND ON MAXSIZE 4G';
    DBMS_OUTPUT.PUT_LINE('created logminer_tbs in ' || SYS_CONTEXT('USERENV','CON_NAME'));
  ELSE
    DBMS_OUTPUT.PUT_LINE('logminer_tbs present in ' || SYS_CONTEXT('USERENV','CON_NAME'));
  END IF;
END;
/

ALTER SESSION SET CONTAINER = CDB$ROOT;
SET SERVEROUTPUT ON

DECLARE
  v_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM dba_users WHERE username = 'C##DBZUSER';
  IF v_cnt = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER c##dbzuser IDENTIFIED BY "Dbz_Th3sis_2026" '
                   || 'DEFAULT TABLESPACE logminer_tbs QUOTA UNLIMITED ON logminer_tbs CONTAINER=ALL';
    DBMS_OUTPUT.PUT_LINE('created c##dbzuser');
  ELSE
    DBMS_OUTPUT.PUT_LINE('c##dbzuser present');
  END IF;
END;
/

GRANT CREATE SESSION, SET CONTAINER             TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$DATABASE                     TO c##dbzuser CONTAINER=ALL;
GRANT FLASHBACK ANY TABLE, SELECT ANY TABLE     TO c##dbzuser CONTAINER=ALL;
GRANT SELECT_CATALOG_ROLE, EXECUTE_CATALOG_ROLE TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ANY TRANSACTION, LOGMINING         TO c##dbzuser CONTAINER=ALL;

-- Debezium's LogMiner strategy creates a LOG_MINING_FLUSH table in the capture user's own
-- schema and writes to it to force LGWR to flush the redo buffer. Without CREATE TABLE and a
-- tablespace quota the connector snapshots successfully, reports RUNNING, and then dies on its
-- first streaming iteration with "Failed to create flush table" caused by ORA-01031. The
-- privilege lists in most Debezium-on-Oracle guides omit this because it is only needed once
-- the connector reaches the streaming phase.
GRANT CREATE TABLE TO c##dbzuser CONTAINER=ALL;

-- The QUOTA clause of CREATE USER ... CONTAINER=ALL does not propagate the quota into each
-- PDB; only the CDB$ROOT quota is established. Verified on this instance: the user was created
-- with QUOTA UNLIMITED ON logminer_tbs CONTAINER=ALL, yet DBA_TS_QUOTAS in OBSVPDB held no row
-- until these statements were issued. Same class of defect as finding 2 — a container-scoped
-- clause that looks global and is not.
ALTER SESSION SET CONTAINER = CDB$ROOT;
ALTER USER c##dbzuser QUOTA UNLIMITED ON logminer_tbs;
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER USER c##dbzuser QUOTA UNLIMITED ON logminer_tbs;
ALTER SESSION SET CONTAINER = OBSVPDB;
ALTER USER c##dbzuser QUOTA UNLIMITED ON logminer_tbs;
ALTER SESSION SET CONTAINER = CDB$ROOT;
SET SERVEROUTPUT ON
GRANT SELECT ON V_$LOG                          TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOG_HISTORY                  TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOGMNR_LOGS                  TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOGMNR_CONTENTS              TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOGFILE                      TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$ARCHIVED_LOG                 TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$ARCHIVE_DEST_STATUS          TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$TRANSACTION                  TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$MYSTAT                       TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$STATNAME                     TO c##dbzuser CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR                    TO c##dbzuser CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR_D                  TO c##dbzuser CONTAINER=ALL;

-- Fail loudly if the user is still absent, rather than reporting a false success.
DECLARE
  v_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM dba_users WHERE username = 'C##DBZUSER';
  IF v_cnt = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'CAPTURE USER MISSING - CDC setup failed');
  END IF;
  DBMS_OUTPUT.PUT_LINE('>>> capture user ready');
END;
/
EXIT;

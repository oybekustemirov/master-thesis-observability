-- CDB-level prerequisites for log-based CDC (Approach 3).
-- Requires a database restart; driven by scripts/setup-oracle.sh, which skips this
-- script entirely when the database is already in ARCHIVELOG mode (idempotency).
SET ECHO ON FEEDBACK ON LINESIZE 200
WHENEVER SQLERROR EXIT 1

SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;

-- FORCE LOGGING closes the NOLOGGING capture gap (assumption A-4). Without it, a
-- direct-path NOLOGGING load is invisible to CDC and the loss is silent.
ALTER DATABASE FORCE LOGGING;

-- Minimal database-level supplemental logging: mandatory for LogMiner.
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Oracle-Managed Files: unset in this image, which makes "DATAFILE SIZE n" fail with
-- ORA-02236. Setting it here lets every later CREATE TABLESPACE use OMF syntax.
ALTER SYSTEM SET DB_CREATE_FILE_DEST='/opt/oracle/oradata' SCOPE=BOTH;

SELECT log_mode, force_logging, supplemental_log_data_min FROM v$database;
EXIT;

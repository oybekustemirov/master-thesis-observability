-- Between runs: clear workload, PRESERVE the reference population so every run starts from
-- an identical account base without paying regeneration cost.
SET FEEDBACK OFF VERIFY OFF SERVEROUTPUT ON
ALTER SESSION SET CONTAINER = OBSVPDB;
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT 1
BEGIN obsv.PKG_SYNTH_DATA.reset_workload; END;
/
-- The AQ backlog must be empty before an AQ run starts. A message left over from a previous
-- run is dequeued by the bridge, republished, and then counted as a PHANTOM event against a
-- ground truth that no longer contains it. Swallowing a failure here would therefore
-- manufacture a reliability defect in a pipeline that has none, so this block is loud and
-- verifies the result instead of assuming it.
DECLARE
  l_before PLS_INTEGER;
  l_after  PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_before FROM obsv.A1_EVT_QT;
  DBMS_AQADM.PURGE_QUEUE_TABLE('OBSV.A1_EVT_QT', NULL, NULL);
  SELECT COUNT(*) INTO l_after FROM obsv.A1_EVT_QT;
  DBMS_OUTPUT.PUT_LINE('AQ backlog purged: ' || l_before || ' -> ' || l_after);
  IF l_after > 0 THEN
    RAISE_APPLICATION_ERROR(-20010,
      'AQ queue table still holds ' || l_after || ' messages after purge');
  END IF;
END;
/
EXIT;

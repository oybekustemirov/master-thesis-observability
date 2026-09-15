-- Approach 1: classic Advanced Queuing. Chosen over TEQ for the PoC because the
-- JMS payload type gives a straightforward Spring bridge; the thesis discusses TEQ as
-- the RAC-appropriate production choice.

DECLARE
  v_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM user_queue_tables WHERE queue_table = 'A1_EVT_QT';
  IF v_cnt = 0 THEN
    DBMS_AQADM.CREATE_QUEUE_TABLE(
      queue_table        => 'A1_EVT_QT',
      queue_payload_type => 'SYS.AQ$_JMS_TEXT_MESSAGE',
      multiple_consumers => TRUE,
      sort_list          => 'ENQ_TIME',
      compatible         => '10.0');

    DBMS_AQADM.CREATE_QUEUE(
      queue_name  => 'A1_EVT_Q',
      queue_table => 'A1_EVT_QT',
      max_retries => 5,
      retry_delay => 2);

    DBMS_AQADM.START_QUEUE(queue_name => 'A1_EVT_Q');

    DBMS_AQADM.ADD_SUBSCRIBER(
      queue_name => 'A1_EVT_Q',
      subscriber => SYS.AQ$_AGENT('OBSERVABILITY_BRIDGE', NULL, NULL));
  END IF;
END;
/

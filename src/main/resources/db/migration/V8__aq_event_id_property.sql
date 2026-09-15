-- Header parity between Approach 1 and Approach 2.
--
-- V5 generated the event id inside the JSON payload only, so an AQ consumer had to parse the
-- body to deduplicate, while an outbox consumer could read the eventId Kafka header directly.
-- That asymmetry would have shown up in the comparison as a latency difference between the
-- two approaches when it is really a difference between two payload conventions.
--
-- Here the id is generated once in emit_state_change and carried BOTH in the payload and as a
-- JMS string property, so the AQ-to-Kafka bridge emits exactly the same header set as the
-- outbox relay and the two pipelines are measured on equal terms.

CREATE OR REPLACE PACKAGE PKG_A1_EVENT AS
  SCHEMA_VERSION CONSTANT VARCHAR2(8) := '1.0.0';
  FUNCTION event_type_for(p_old IN VARCHAR2, p_new IN VARCHAR2) RETURN VARCHAR2;
  FUNCTION build_payload(p_event_id IN VARCHAR2, p_txn_id IN NUMBER, p_type IN VARCHAR2,
                         p_old IN VARCHAR2, p_new IN VARCHAR2,
                         p_source IN VARCHAR2) RETURN CLOB;
  PROCEDURE publish(p_event_id IN VARCHAR2, p_event_type IN VARCHAR2,
                    p_aggregate_id IN VARCHAR2, p_event_seq IN NUMBER, p_payload IN CLOB);
  PROCEDURE emit_state_change(p_txn_id IN NUMBER, p_old_status IN VARCHAR2,
                              p_new_status IN VARCHAR2, p_source IN VARCHAR2 DEFAULT 'TRIGGER');
END PKG_A1_EVENT;
/

CREATE OR REPLACE PACKAGE BODY PKG_A1_EVENT AS

  FUNCTION event_type_for(p_old IN VARCHAR2, p_new IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE
             WHEN p_old IS NULL       THEN 'A1TransactionInitiated'
             WHEN p_new = 'VALIDATED' THEN 'A1TransactionValidated'
             WHEN p_new = 'PROCESSED' THEN 'A1TransactionProcessed'
             WHEN p_new = 'REJECTED'  THEN 'A1TransactionRejected'
             ELSE NULL
           END;
  END event_type_for;

  FUNCTION build_payload(p_event_id IN VARCHAR2, p_txn_id IN NUMBER, p_type IN VARCHAR2,
                         p_old IN VARCHAR2, p_new IN VARCHAR2,
                         p_source IN VARCHAR2) RETURN CLOB IS
    l_row  TXN_A1%ROWTYPE;
    l_json CLOB;
  BEGIN
    SELECT * INTO l_row FROM TXN_A1 WHERE TXN_ID = p_txn_id;
    -- JSON_OBJECT(... RETURNING CLOB) cannot be used as a PL/SQL expression on this
    -- release (PLS-00684); it must be evaluated in SQL context. The consequence is a
    -- mandatory PL/SQL-to-SQL context switch per emitted event, which is a real and
    -- measurable cost specific to Approach 1 and is reported in the results chapter.
    SELECT JSON_OBJECT(
      'eventId'       VALUE p_event_id,
      'eventType'     VALUE p_type,
      'schemaVersion' VALUE SCHEMA_VERSION,
      'occurredAt'    VALUE TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'UTC',
                                    'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'),
      'sourceSystem'  VALUE p_source,
      'txnId'         VALUE p_txn_id,
      'txnRef'        VALUE l_row.TXN_REF,
      'debitAccount'  VALUE l_row.DEBIT_ACCOUNT,
      'creditAccount' VALUE l_row.CREDIT_ACCOUNT,
      'amount'        VALUE l_row.AMOUNT,
      'currency'      VALUE l_row.CURRENCY,
      'channel'       VALUE l_row.CHANNEL,
      'oldStatus'     VALUE p_old,
      'newStatus'     VALUE p_new,
      'rejectCode'    VALUE l_row.REJECT_CODE,
      'traceId'       VALUE SYS_CONTEXT('CLIENTCONTEXT','trace_id')
      RETURNING CLOB)
      INTO l_json FROM dual;
    RETURN l_json;
  END build_payload;

  PROCEDURE publish(p_event_id IN VARCHAR2, p_event_type IN VARCHAR2,
                    p_aggregate_id IN VARCHAR2, p_event_seq IN NUMBER, p_payload IN CLOB) IS
    l_enq_opt  DBMS_AQ.ENQUEUE_OPTIONS_T;
    l_msg_prop DBMS_AQ.MESSAGE_PROPERTIES_T;
    l_msg_id   RAW(16);
    l_msg      SYS.AQ$_JMS_TEXT_MESSAGE;
  BEGIN
    l_msg := SYS.AQ$_JMS_TEXT_MESSAGE.construct;
    l_msg.set_text(p_payload);
    -- Set as JMS properties so the bridge can build Kafka headers without parsing the body.
    l_msg.set_string_property('eventId',       p_event_id);
    l_msg.set_string_property('eventType',     p_event_type);
    l_msg.set_string_property('aggregateId',   p_aggregate_id);
    l_msg.set_string_property('schemaVersion', SCHEMA_VERSION);
    l_msg.set_int_property   ('eventSeq',      p_event_seq);
    l_msg_prop.correlation := p_aggregate_id;
    l_msg_prop.expiration  := DBMS_AQ.NEVER;

    -- The defining property of Approach 1: the message becomes visible to subscribers
    -- only when the business transaction commits, and is rolled back if it does not.
    l_enq_opt.visibility := DBMS_AQ.ON_COMMIT;

    DBMS_AQ.ENQUEUE(queue_name         => 'A1_EVT_Q',
                    enqueue_options    => l_enq_opt,
                    message_properties => l_msg_prop,
                    payload            => l_msg,
                    msgid              => l_msg_id);
  END publish;

  PROCEDURE emit_state_change(p_txn_id IN NUMBER, p_old_status IN VARCHAR2,
                              p_new_status IN VARCHAR2, p_source IN VARCHAR2 DEFAULT 'TRIGGER') IS
    l_type     VARCHAR2(64) := event_type_for(p_old_status, p_new_status);
    l_event_id VARCHAR2(32);
  BEGIN
    IF l_type IS NULL THEN RETURN; END IF;
    -- Generated once and used twice, so the payload id and the header id can never diverge.
    l_event_id := RAWTOHEX(SYS_GUID());
    publish(l_event_id, l_type, TO_CHAR(p_txn_id), NEXT_EVT_SEQ(p_txn_id),
            build_payload(l_event_id, p_txn_id, l_type, p_old_status, p_new_status, p_source));
  END emit_state_change;

END PKG_A1_EVENT;
/

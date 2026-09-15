-- Approach 1: event factory and the capture trigger.
-- The trigger is created DISABLED; the experiment harness enables exactly one capture
-- mechanism per run so that modes never overlap.

CREATE OR REPLACE PACKAGE PKG_A1_EVENT AS
  SCHEMA_VERSION CONSTANT VARCHAR2(8) := '1.0.0';
  FUNCTION event_type_for(p_old IN VARCHAR2, p_new IN VARCHAR2) RETURN VARCHAR2;
  FUNCTION build_payload(p_txn_id IN NUMBER, p_type IN VARCHAR2,
                         p_old IN VARCHAR2, p_new IN VARCHAR2,
                         p_source IN VARCHAR2) RETURN CLOB;
  PROCEDURE publish(p_event_type IN VARCHAR2, p_aggregate_id IN VARCHAR2,
                    p_event_seq IN NUMBER, p_payload IN CLOB);
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

  FUNCTION build_payload(p_txn_id IN NUMBER, p_type IN VARCHAR2,
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
      'eventId'       VALUE RAWTOHEX(SYS_GUID()),
      'eventType'     VALUE p_type,
      'schemaVersion' VALUE SCHEMA_VERSION,
      'occurredAt'    VALUE TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'UTC',
                                    'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'),
      'sourceSystem'  VALUE p_source,
      'txnId'         VALUE p_txn_id,
      'txnRef'        VALUE l_row.TXN_REF,
      'debitAccount'     VALUE l_row.DEBIT_ACCOUNT,
      'creditAccount'    VALUE l_row.CREDIT_ACCOUNT,
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

  PROCEDURE publish(p_event_type IN VARCHAR2, p_aggregate_id IN VARCHAR2,
                    p_event_seq IN NUMBER, p_payload IN CLOB) IS
    l_enq_opt  DBMS_AQ.ENQUEUE_OPTIONS_T;
    l_msg_prop DBMS_AQ.MESSAGE_PROPERTIES_T;
    l_msg_id   RAW(16);
    l_msg      SYS.AQ$_JMS_TEXT_MESSAGE;
  BEGIN
    l_msg := SYS.AQ$_JMS_TEXT_MESSAGE.construct;
    l_msg.set_text(p_payload);
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
    l_type VARCHAR2(64) := event_type_for(p_old_status, p_new_status);
  BEGIN
    IF l_type IS NULL THEN RETURN; END IF;
    publish(l_type, TO_CHAR(p_txn_id), NEXT_EVT_SEQ(p_txn_id),
            build_payload(p_txn_id, l_type, p_old_status, p_new_status, p_source));
  END emit_state_change;

END PKG_A1_EVENT;
/

CREATE OR REPLACE TRIGGER TRG_TXN_A1_AQ
FOR INSERT OR UPDATE OF STATUS ON TXN_A1
COMPOUND TRIGGER
  TYPE t_chg IS RECORD (txn_id NUMBER, old_status VARCHAR2(16), new_status VARCHAR2(16));
  TYPE t_buf IS TABLE OF t_chg INDEX BY PLS_INTEGER;
  g_buf t_buf;

  AFTER EACH ROW IS
  BEGIN
    -- Emit only on a material state transition: suppressing no-op updates is the single
    -- most effective way to limit redo amplification in this approach.
    IF INSERTING OR :NEW.STATUS <> :OLD.STATUS THEN
      g_buf(g_buf.COUNT + 1).txn_id := :NEW.TXN_ID;
      g_buf(g_buf.COUNT).old_status := CASE WHEN UPDATING THEN :OLD.STATUS END;
      g_buf(g_buf.COUNT).new_status := :NEW.STATUS;
    END IF;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
  BEGIN
    FOR i IN 1 .. g_buf.COUNT LOOP
      PKG_A1_EVENT.emit_state_change(g_buf(i).txn_id, g_buf(i).old_status,
                                     g_buf(i).new_status, 'TRIGGER');
    END LOOP;
    g_buf.DELETE;
    -- Deliberately no exception handler. Swallowing an error would silently drop an A1
    -- event; the failure must be loud. This is the availability/reliability coupling of
    -- Approach 1, made explicit in code and measured by fault case F8.
  END AFTER STATEMENT;
END;
/

ALTER TRIGGER TRG_TXN_A1_AQ DISABLE;

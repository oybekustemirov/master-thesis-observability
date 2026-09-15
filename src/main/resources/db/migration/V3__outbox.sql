-- Transactional outbox (Approach 2 variant B3, and the store of the recommended hybrid).
-- Insert-only by design: no UPDATEs ever occur, which is what makes ALL-COLUMN
-- supplemental logging on this table nearly free when Debezium relays it.

CREATE TABLE A1_EVENT_OUTBOX (
  ID              NUMBER(19) GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  EVENT_ID        RAW(16)       NOT NULL,
  AGGREGATE_TYPE  VARCHAR2(64)  NOT NULL,
  AGGREGATE_ID    VARCHAR2(64)  NOT NULL,
  EVENT_TYPE      VARCHAR2(64)  NOT NULL,
  EVENT_SEQ       NUMBER(19)    NOT NULL,
  SCHEMA_VERSION  VARCHAR2(16)  DEFAULT '1.0.0' NOT NULL,
  TRACE_ID        VARCHAR2(32),
  SPAN_ID         VARCHAR2(16),
  SOURCE_SYSTEM   VARCHAR2(32)  NOT NULL,
  PAYLOAD         CLOB          NOT NULL,
  CREATED_AT      TIMESTAMP(6)  DEFAULT SYSTIMESTAMP NOT NULL,
  PUBLISHED_AT    TIMESTAMP(6),
  ATTEMPTS        NUMBER(5)     DEFAULT 0 NOT NULL,
  CONSTRAINT CK_OUTBOX_JSON CHECK (PAYLOAD IS JSON)
);

CREATE UNIQUE INDEX UQ_OUTBOX_EVENT_ID ON A1_EVENT_OUTBOX (EVENT_ID);

-- Function-based index: only unpublished rows are indexed, so the relay's claim query
-- stays O(backlog) rather than O(table) however large the history grows.
CREATE INDEX IX_OUTBOX_PENDING
  ON A1_EVENT_OUTBOX (CASE WHEN PUBLISHED_AT IS NULL THEN 1 END, ID);

-- Shared publication API. The Spring OutboxWriter and legacy PL/SQL batches both write
-- through the SAME contract, which is what gives the hybrid complete writer coverage.
-- Deliberately no COMMIT and no PRAGMA AUTONOMOUS_TRANSACTION: the caller's transaction
-- owns the commit. An autonomous transaction here would emit events for business
-- transactions that later roll back, which is strictly worse than losing them.
CREATE OR REPLACE PROCEDURE EMIT_A1_EVENT(
    p_aggregate_id IN VARCHAR2,
    p_event_type   IN VARCHAR2,
    p_source       IN VARCHAR2,
    p_payload      IN CLOB) IS
BEGIN
  INSERT INTO A1_EVENT_OUTBOX
    (EVENT_ID, AGGREGATE_TYPE, AGGREGATE_ID, EVENT_TYPE, EVENT_SEQ,
     SCHEMA_VERSION, TRACE_ID, SOURCE_SYSTEM, PAYLOAD)
  VALUES
    (SYS_GUID(), 'a1.transaction', p_aggregate_id, p_event_type,
     SEQ_A1_EVENT.NEXTVAL, '1.0.0',
     SYS_CONTEXT('CLIENTCONTEXT','trace_id'), p_source, p_payload);
END;
/

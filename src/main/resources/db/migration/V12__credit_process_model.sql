-- The credit application process: the workflow this thesis's observability is FOR.
--
-- Chapters 1-6 answer "which mechanism captures state changes reliably, and what does each cost
-- the database". That is the means. This is the end: a workflow whose stages are measured in
-- hours and days and involve people, where the operational question is not "did the event
-- arrive" but "where does the time actually go".
--
-- TXN_A1 cannot answer that question. It is a payment transfer whose whole lifecycle completes
-- in milliseconds; it was the right subject for measuring a capture mechanism and is the wrong
-- one for measuring a process. A credit application is the opposite on both counts, which is why
-- the two coexist rather than one replacing the other.
--
-- ASSUMPTION, stated because it is not measured: the stage model below is a typical retail
-- credit process, not this bank's actual one. Stages are held in a TABLE rather than a CHECK
-- constraint or an enum precisely so that replacing them with the real ones is configuration
-- rather than a schema change.

-- ---------------------------------------------------------------- stages ----
CREATE TABLE CREDIT_STAGE (
  STAGE_CODE   VARCHAR2(24)  PRIMARY KEY,
  SEQ          NUMBER(3)     NOT NULL,
  STAGE_NAME   VARCHAR2(64)  NOT NULL,
  -- AUTOMATED: no human, no queue. HUMAN: waits in a queue, then someone works on it.
  -- CUSTOMER: the bank is waiting on the applicant, which is time the bank does not control
  -- and must not be confused with the bank's own handling time.
  STAGE_TYPE   VARCHAR2(12)  NOT NULL,
  SLA_HOURS    NUMBER(6,2),
  CONSTRAINT CK_STAGE_TYPE CHECK (STAGE_TYPE IN ('AUTOMATED','HUMAN','CUSTOMER'))
);

INSERT INTO CREDIT_STAGE VALUES ('SUBMITTED',       1, 'Application submitted',      'AUTOMATED', 0.1);
INSERT INTO CREDIT_STAGE VALUES ('DOCS_REQUESTED',  2, 'Documents requested',        'CUSTOMER',  48);
INSERT INTO CREDIT_STAGE VALUES ('DOCS_RECEIVED',   3, 'Documents received',         'AUTOMATED', 0.2);
INSERT INTO CREDIT_STAGE VALUES ('DOCS_VERIFIED',   4, 'Documents verified',         'HUMAN',     4);
INSERT INTO CREDIT_STAGE VALUES ('SCORING',         5, 'Credit scoring',             'AUTOMATED', 0.1);
INSERT INTO CREDIT_STAGE VALUES ('UNDERWRITING',    6, 'Underwriting review',        'HUMAN',     8);
INSERT INTO CREDIT_STAGE VALUES ('DECISION',        7, 'Decision issued',            'AUTOMATED', 0.1);
INSERT INTO CREDIT_STAGE VALUES ('CONTRACT_SIGNED', 8, 'Contract signed',            'CUSTOMER',  72);
INSERT INTO CREDIT_STAGE VALUES ('DISBURSED',       9, 'Funds disbursed',            'HUMAN',     2);
INSERT INTO CREDIT_STAGE VALUES ('REJECTED',       99, 'Application rejected',       'AUTOMATED', 0.1);
INSERT INTO CREDIT_STAGE VALUES ('WITHDRAWN',      98, 'Withdrawn by applicant',     'CUSTOMER',  0.1);
COMMIT;

-- ------------------------------------------------------------- the staff ----
-- No personal data: an identifier, a role and a branch. Nothing that identifies a human being.
CREATE TABLE CREDIT_STAFF (
  STAFF_ID     VARCHAR2(16)  PRIMARY KEY,
  STAFF_ROLE   VARCHAR2(24)  NOT NULL,
  BRANCH_CODE  VARCHAR2(8)   NOT NULL,
  -- Relative speed. A team is not uniform, and a process analysis that assumes it is cannot
  -- distinguish "this stage is slow" from "this stage is understaffed on one shift".
  SPEED_FACTOR NUMBER(4,2)   DEFAULT 1.0 NOT NULL
);

-- ------------------------------------------------------ the applications ----
CREATE TABLE CREDIT_APPLICATION (
  APP_ID        NUMBER(19)   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  APP_REF       VARCHAR2(64) NOT NULL,
  CUSTOMER_REF  VARCHAR2(32) NOT NULL,
  PRODUCT       VARCHAR2(16) NOT NULL,
  AMOUNT        NUMBER(19,4) NOT NULL,
  CURRENCY      VARCHAR2(3)  DEFAULT 'UZS' NOT NULL,
  CHANNEL       VARCHAR2(16) NOT NULL,
  BRANCH_CODE   VARCHAR2(8)  NOT NULL,
  CURRENT_STAGE VARCHAR2(24) NOT NULL,
  OUTCOME       VARCHAR2(16),
  SUBMITTED_AT  TIMESTAMP(6) NOT NULL,
  CLOSED_AT     TIMESTAMP(6),
  CONSTRAINT UQ_CREDIT_APP_REF UNIQUE (APP_REF),
  CONSTRAINT FK_APP_STAGE FOREIGN KEY (CURRENT_STAGE) REFERENCES CREDIT_STAGE (STAGE_CODE)
);

-- ------------------------------------------------------- the event log ----
-- One row per stage transition. This is the process-mining event log: a case, an activity, a
-- timestamp and a resource — plus the decomposition that makes it actionable.
--
-- ENTERED_AT / PICKED_UP_AT / COMPLETED_AT separate two quantities that a single duration
-- column would fuse into one useless number:
--
--   queue wait = PICKED_UP_AT - ENTERED_AT   time the case sat untouched
--   work time  = COMPLETED_AT - PICKED_UP_AT time someone actually spent on it
--
-- An application that waits two days in an underwriting queue and an underwriter who spends two
-- days on it are different problems with different remedies — more staff versus better tooling.
-- Reporting only "underwriting took two days" cannot tell them apart, and that is the single
-- most common way a process analysis produces a confident wrong answer.
CREATE TABLE CREDIT_STAGE_EVENT (
  EVENT_ID      NUMBER(19)   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  APP_ID        NUMBER(19)   NOT NULL,
  FROM_STAGE    VARCHAR2(24),
  TO_STAGE      VARCHAR2(24) NOT NULL,
  ENTERED_AT    TIMESTAMP(6) NOT NULL,
  PICKED_UP_AT  TIMESTAMP(6),
  COMPLETED_AT  TIMESTAMP(6) NOT NULL,
  ACTOR_ID      VARCHAR2(16),
  ACTOR_ROLE    VARCHAR2(24),
  BRANCH_CODE   VARCHAR2(8)  NOT NULL,
  -- TRUE when the case came back to a stage it had already passed. Rework is invisible in an
  -- average and is often where the time actually goes.
  IS_REWORK     NUMBER(1)    DEFAULT 0 NOT NULL,
  CONSTRAINT FK_EVT_APP   FOREIGN KEY (APP_ID)   REFERENCES CREDIT_APPLICATION (APP_ID),
  CONSTRAINT FK_EVT_STAGE FOREIGN KEY (TO_STAGE) REFERENCES CREDIT_STAGE (STAGE_CODE)
);

CREATE INDEX IX_EVT_APP   ON CREDIT_STAGE_EVENT (APP_ID, COMPLETED_AT);
CREATE INDEX IX_EVT_STAGE ON CREDIT_STAGE_EVENT (TO_STAGE, COMPLETED_AT);

-- Parameters of the generated process, recorded with every dataset so the numbers in the
-- results chapter can be traced to the assumptions that produced them.
CREATE TABLE CREDIT_SYNTH_CONFIG (
  RUN_ID       NUMBER(10)   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  GENERATED_AT TIMESTAMP(6) DEFAULT SYSTIMESTAMP NOT NULL,
  APPLICATIONS NUMBER(10)   NOT NULL,
  DAYS_SPAN    NUMBER(6)    NOT NULL,
  NOTES        VARCHAR2(400)
);

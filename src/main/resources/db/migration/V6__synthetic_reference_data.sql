-- ============================================================================
-- SYNTHETIC REFERENCE DATA AND WORKLOAD GENERATOR
-- ============================================================================
-- The thesis deliberately uses NO production banking data. That decision is made on
-- information-security grounds, and it also strengthens the work methodologically:
--
--   * Reproducibility — the generator and its parameters ship with the thesis, so any
--     reader can regenerate the exact dataset and re-run the experiments. An experiment
--     on production data could never be independently verified.
--   * Control — transaction rate, currency mix, channel mix and amount distribution must
--     be held constant across modes for the comparison to be valid. Replaying production
--     traffic at a controlled rate is not practical.
--   * Destructive testing — the fault-injection matrix requires purging archive logs,
--     killing instances and deliberately breaking triggers. None of that is permissible
--     against a shared database holding real customer records.
--
-- NO PERSONAL DATA IS GENERATED. Customers carry a reference and a segment; no names,
-- no addresses, no dates of birth. Personal attributes play no part in the A1 workflow
-- being measured, so omitting them removes all re-identification risk at zero cost to
-- the experiment's validity.
--
-- DISTRIBUTION PARAMETERS ARE ASSUMPTIONS, recorded in SYNTH_CONFIG and reported as such
-- in the thesis. They are plausible retail-banking values, not measurements. If aggregate
-- statistics from a production-like environment become available (row counts, status
-- distribution, amount percentiles, intraday volume curve — none of which are sensitive),
-- the generator can be recalibrated by updating SYNTH_CONFIG alone.
-- ============================================================================

CREATE TABLE CUSTOMER (
  CUSTOMER_ID   NUMBER(19)   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  CUSTOMER_REF  VARCHAR2(24) NOT NULL,
  SEGMENT       VARCHAR2(12) NOT NULL,
  BRANCH_CODE   VARCHAR2(5)  NOT NULL,
  RISK_RATING   VARCHAR2(8)  NOT NULL,
  OPENED_AT     DATE         NOT NULL,
  CONSTRAINT UQ_CUSTOMER_REF UNIQUE (CUSTOMER_REF),
  CONSTRAINT CK_CUSTOMER_SEG CHECK (SEGMENT IN ('RETAIL','SME','CORPORATE')),
  CONSTRAINT CK_CUSTOMER_RSK CHECK (RISK_RATING IN ('LOW','MEDIUM','HIGH'))
);

-- Synthetic 20-digit domestic account scheme, structurally similar to a real Uzbek
-- account number but with entirely fabricated values:
--   [1-5]   balance account code   (20208 demand deposit, 20206 settlement, ...)
--   [6-8]   ISO 4217 numeric currency (860 UZS, 840 USD, 978 EUR, 643 RUB)
--   [9-12]  synthetic branch code
--   [13-20] account serial
CREATE TABLE ACCOUNT (
  ACCOUNT_ID    NUMBER(19)   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ACCOUNT_NO    VARCHAR2(34) NOT NULL,
  CUSTOMER_ID   NUMBER(19)   NOT NULL,
  CURRENCY      VARCHAR2(3)  NOT NULL,
  ACCOUNT_TYPE  VARCHAR2(16) NOT NULL,
  STATUS        VARCHAR2(12) DEFAULT 'ACTIVE' NOT NULL,
  BALANCE       NUMBER(19,4) DEFAULT 0 NOT NULL,
  OPENED_AT     DATE         NOT NULL,
  CONSTRAINT UQ_ACCOUNT_NO  UNIQUE (ACCOUNT_NO),
  CONSTRAINT FK_ACCOUNT_CUS FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMER (CUSTOMER_ID),
  CONSTRAINT CK_ACCOUNT_ST  CHECK (STATUS IN ('ACTIVE','BLOCKED','CLOSED'))
);

CREATE INDEX IX_ACCOUNT_CUSTOMER ON ACCOUNT (CUSTOMER_ID);
CREATE INDEX IX_ACCOUNT_CURRENCY ON ACCOUNT (CURRENCY, STATUS);

-- TXN_A1 deliberately carries account NUMBERS, not foreign keys to ACCOUNT. This is both
-- realistic (a counterparty account often belongs to another institution and cannot be a
-- foreign key) and methodologically necessary: adding FK validation to TXN_A1 would change
-- the DML cost being measured and confound the comparison between modes.

-- Every generation run is recorded, so any result in the thesis can be traced back to the
-- exact parameters and random seed that produced its dataset.
CREATE TABLE SYNTH_CONFIG (
  RUN_ID        NUMBER(19)   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  GENERATED_AT  TIMESTAMP(6) DEFAULT SYSTIMESTAMP NOT NULL,
  RANDOM_SEED   NUMBER       NOT NULL,
  CUSTOMERS     NUMBER       NOT NULL,
  ACCOUNTS      NUMBER       NOT NULL,
  TRANSACTIONS  NUMBER       DEFAULT 0 NOT NULL,
  PARAMETERS    CLOB         NOT NULL
);

-- Deterministic synthetic data generator. Seeded via DBMS_RANDOM.SEED so that a given
-- seed always produces the identical dataset, which is what makes the experiments
-- reproducible by a third party.

CREATE OR REPLACE PACKAGE PKG_SYNTH_DATA AS

  -- Assumed distributions. Plausible retail-banking values, NOT measurements.
  -- Recorded in SYNTH_CONFIG with every run and reported as assumptions in the thesis.
  PCT_CUR_UZS   CONSTANT NUMBER := 85;
  PCT_CUR_USD   CONSTANT NUMBER := 10;
  PCT_CUR_EUR   CONSTANT NUMBER := 4;
  PCT_SEG_RETAIL    CONSTANT NUMBER := 88;
  PCT_SEG_SME       CONSTANT NUMBER := 10;
  PCT_CH_MOBILE CONSTANT NUMBER := 55;
  PCT_CH_WEB    CONSTANT NUMBER := 25;
  PCT_CH_ATM    CONSTANT NUMBER := 10;
  PCT_CH_BRANCH CONSTANT NUMBER := 7;
  -- Share of A1 transactions that terminate in REJECTED rather than PROCESSED
  PCT_REJECTED  CONSTANT NUMBER := 4;
  -- Log-normal amount parameters per segment: amount = EXP(mu + sigma * N(0,1)) in UZS.
  -- RETAIL mu=13.1 gives a median near 490 000 UZS and a p99 near 40 000 000 UZS.
  MU_RETAIL     CONSTANT NUMBER := 13.1;
  SIGMA_RETAIL  CONSTANT NUMBER := 1.9;
  MU_SME        CONSTANT NUMBER := 15.4;
  SIGMA_SME     CONSTANT NUMBER := 1.6;
  MU_CORPORATE  CONSTANT NUMBER := 17.2;
  SIGMA_CORP    CONSTANT NUMBER := 1.4;

  FUNCTION rand_currency  RETURN VARCHAR2;
  FUNCTION rand_segment   RETURN VARCHAR2;
  FUNCTION rand_channel   RETURN VARCHAR2;
  FUNCTION rand_amount(p_segment IN VARCHAR2, p_currency IN VARCHAR2) RETURN NUMBER;
  FUNCTION pick_account(p_currency IN VARCHAR2) RETURN VARCHAR2;

  PROCEDURE generate_reference(p_customers IN NUMBER  DEFAULT 50000,
                               p_seed      IN NUMBER  DEFAULT 20260902);

  -- Bulk transaction generator. Doubles as the "legacy batch writer" of assumption A-3:
  -- it writes A1 transactions WITHOUT going through the Spring application, which is
  -- exactly the blind spot of the wrapper approach and the subject of fault case F11.
  PROCEDURE generate_transactions(p_count      IN NUMBER,
                                  p_source     IN VARCHAR2 DEFAULT 'BATCH_EOD',
                                  p_advance    IN BOOLEAN  DEFAULT TRUE,
                                  p_commit_every IN NUMBER DEFAULT 5000);

  PROCEDURE reset_workload;
END PKG_SYNTH_DATA;
/

CREATE OR REPLACE PACKAGE BODY PKG_SYNTH_DATA AS

  -- Account pool cached in PGA. Selecting a random account with
  -- "ORDER BY DBMS_RANDOM.VALUE" would sort the whole ACCOUNT table on EVERY call, which
  -- makes generating a 500 000-row batch quadratic and unusable. The pool is loaded once
  -- per generate_transactions call and indexed in O(1).
  TYPE t_accs IS TABLE OF ACCOUNT.ACCOUNT_NO%TYPE INDEX BY PLS_INTEGER;
  TYPE t_pool IS TABLE OF t_accs INDEX BY VARCHAR2(3);
  g_pool t_pool;

  PROCEDURE load_pool IS
  BEGIN
    g_pool.DELETE;
    FOR c IN (SELECT DISTINCT currency FROM ACCOUNT WHERE status = 'ACTIVE') LOOP
      SELECT account_no BULK COLLECT INTO g_pool(c.currency)
        FROM ACCOUNT WHERE currency = c.currency AND status = 'ACTIVE';
    END LOOP;
  END load_pool;


  FUNCTION pct RETURN NUMBER IS BEGIN RETURN DBMS_RANDOM.VALUE(0, 100); END;

  FUNCTION rand_currency RETURN VARCHAR2 IS
    p NUMBER := pct;
  BEGIN
    RETURN CASE
             WHEN p < PCT_CUR_UZS                             THEN 'UZS'
             WHEN p < PCT_CUR_UZS + PCT_CUR_USD               THEN 'USD'
             WHEN p < PCT_CUR_UZS + PCT_CUR_USD + PCT_CUR_EUR THEN 'EUR'
             ELSE 'RUB'
           END;
  END rand_currency;

  FUNCTION rand_segment RETURN VARCHAR2 IS
    p NUMBER := pct;
  BEGIN
    RETURN CASE
             WHEN p < PCT_SEG_RETAIL                   THEN 'RETAIL'
             WHEN p < PCT_SEG_RETAIL + PCT_SEG_SME     THEN 'SME'
             ELSE 'CORPORATE'
           END;
  END rand_segment;

  FUNCTION rand_channel RETURN VARCHAR2 IS
    p NUMBER := pct;
  BEGIN
    RETURN CASE
             WHEN p < PCT_CH_MOBILE                                      THEN 'MOBILE'
             WHEN p < PCT_CH_MOBILE + PCT_CH_WEB                         THEN 'WEB'
             WHEN p < PCT_CH_MOBILE + PCT_CH_WEB + PCT_CH_ATM            THEN 'ATM'
             WHEN p < PCT_CH_MOBILE + PCT_CH_WEB + PCT_CH_ATM + PCT_CH_BRANCH THEN 'BRANCH'
             ELSE 'API'
           END;
  END rand_channel;

  FUNCTION rand_amount(p_segment IN VARCHAR2, p_currency IN VARCHAR2) RETURN NUMBER IS
    l_mu    NUMBER;
    l_sigma NUMBER;
    l_uzs   NUMBER;
  BEGIN
    CASE p_segment
      WHEN 'RETAIL'    THEN l_mu := MU_RETAIL;    l_sigma := SIGMA_RETAIL;
      WHEN 'SME'       THEN l_mu := MU_SME;       l_sigma := SIGMA_SME;
      ELSE                  l_mu := MU_CORPORATE; l_sigma := SIGMA_CORP;
    END CASE;
    l_uzs := EXP(l_mu + l_sigma * DBMS_RANDOM.NORMAL);
    -- Convert to the transaction currency using fixed indicative rates. Exact rates are
    -- irrelevant to the experiment; only the shape of the distribution matters.
    RETURN CASE p_currency
             WHEN 'UZS' THEN ROUND(l_uzs, 0)
             WHEN 'USD' THEN ROUND(l_uzs / 12600, 2)
             WHEN 'EUR' THEN ROUND(l_uzs / 13700, 2)
             ELSE            ROUND(l_uzs / 135,   2)
           END;
  END rand_amount;

  FUNCTION pick_account(p_currency IN VARCHAR2) RETURN VARCHAR2 IS
    l_n PLS_INTEGER;
  BEGIN
    IF NOT g_pool.EXISTS(p_currency) THEN load_pool; END IF;
    IF NOT g_pool.EXISTS(p_currency) THEN RETURN NULL; END IF;
    l_n := g_pool(p_currency).COUNT;
    IF l_n = 0 THEN RETURN NULL; END IF;
    RETURN g_pool(p_currency)(TRUNC(DBMS_RANDOM.VALUE(1, l_n + 1)));
  END pick_account;

  PROCEDURE generate_reference(p_customers IN NUMBER DEFAULT 50000,
                               p_seed      IN NUMBER DEFAULT 20260902) IS
    TYPE t_cust IS TABLE OF CUSTOMER%ROWTYPE INDEX BY PLS_INTEGER;
    l_accounts   NUMBER := 0;
    l_branch     VARCHAR2(5);
    l_segment    VARCHAR2(12);
    l_currency   VARCHAR2(3);
    l_cur_num    VARCHAR2(3);
    l_n_acc      PLS_INTEGER;
    l_serial     NUMBER := 0;
    l_cust_id    NUMBER;
    l_risk       VARCHAR2(8);
    l_acc_status VARCHAR2(12);
    l_p          NUMBER;
  BEGIN
    DBMS_RANDOM.SEED(p_seed);

    FOR i IN 1 .. p_customers LOOP
      l_segment := rand_segment;
      l_branch  := LPAD(TRUNC(DBMS_RANDOM.VALUE(1, 60)), 5, '0');

      l_p := pct;
      l_risk := CASE WHEN l_p < 80 THEN 'LOW' WHEN l_p < 97 THEN 'MEDIUM' ELSE 'HIGH' END;

      INSERT INTO CUSTOMER (CUSTOMER_REF, SEGMENT, BRANCH_CODE, RISK_RATING, OPENED_AT)
      VALUES ('CUST-' || LPAD(i, 9, '0'), l_segment, l_branch, l_risk,
              SYSDATE - TRUNC(DBMS_RANDOM.VALUE(30, 3650)))
      RETURNING CUSTOMER_ID INTO l_cust_id;

      -- Retail customers hold 1-2 accounts, business customers 2-4.
      l_n_acc := CASE WHEN l_segment = 'RETAIL'
                      THEN TRUNC(DBMS_RANDOM.VALUE(1, 3))
                      ELSE TRUNC(DBMS_RANDOM.VALUE(2, 5)) END;

      FOR a IN 1 .. l_n_acc LOOP
        l_serial   := l_serial + 1;
        -- First account is always UZS, so every customer has a domestic-currency account.
        l_currency := CASE WHEN a = 1 THEN 'UZS' ELSE rand_currency END;
        l_cur_num  := CASE l_currency WHEN 'UZS' THEN '860' WHEN 'USD' THEN '840'
                                      WHEN 'EUR' THEN '978' ELSE '643' END;

        l_p := pct;
        l_acc_status := CASE WHEN l_p < 98 THEN 'ACTIVE'
                             WHEN l_p < 99.5 THEN 'BLOCKED' ELSE 'CLOSED' END;

        INSERT INTO ACCOUNT (ACCOUNT_NO, CUSTOMER_ID, CURRENCY, ACCOUNT_TYPE, STATUS,
                             BALANCE, OPENED_AT)
        VALUES (CASE WHEN l_segment = 'RETAIL' THEN '20208' ELSE '20206' END
                  || l_cur_num || LPAD(l_branch, 4, '0') || LPAD(l_serial, 8, '0'),
                l_cust_id,
                l_currency,
                CASE WHEN l_segment = 'RETAIL' THEN 'CURRENT' ELSE 'SETTLEMENT' END,
                l_acc_status,
                ROUND(EXP(14 + DBMS_RANDOM.NORMAL), 0),
                SYSDATE - TRUNC(DBMS_RANDOM.VALUE(1, 3000)));
        l_accounts := l_accounts + 1;
      END LOOP;

      IF MOD(i, 5000) = 0 THEN COMMIT; END IF;
    END LOOP;
    COMMIT;

    INSERT INTO SYNTH_CONFIG (RANDOM_SEED, CUSTOMERS, ACCOUNTS, PARAMETERS)
    VALUES (p_seed, p_customers, l_accounts,
            JSON_OBJECT('currencyMix' VALUE JSON_OBJECT('UZS' VALUE PCT_CUR_UZS,
                                                        'USD' VALUE PCT_CUR_USD,
                                                        'EUR' VALUE PCT_CUR_EUR),
                        'segmentMix'  VALUE JSON_OBJECT('RETAIL' VALUE PCT_SEG_RETAIL,
                                                        'SME'    VALUE PCT_SEG_SME),
                        'channelMix'  VALUE JSON_OBJECT('MOBILE' VALUE PCT_CH_MOBILE,
                                                        'WEB'    VALUE PCT_CH_WEB,
                                                        'ATM'    VALUE PCT_CH_ATM,
                                                        'BRANCH' VALUE PCT_CH_BRANCH),
                        'rejectedPct' VALUE PCT_REJECTED,
                        'amountLogNormal' VALUE JSON_OBJECT('muRetail' VALUE MU_RETAIL,
                                                            'sigmaRetail' VALUE SIGMA_RETAIL)
                        RETURNING CLOB));
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('generated ' || p_customers || ' customers, ' || l_accounts || ' accounts');
  END generate_reference;

  PROCEDURE generate_transactions(p_count        IN NUMBER,
                                  p_source       IN VARCHAR2 DEFAULT 'BATCH_EOD',
                                  p_advance      IN BOOLEAN  DEFAULT TRUE,
                                  p_commit_every IN NUMBER   DEFAULT 5000) IS
    l_currency VARCHAR2(3);
    l_segment  VARCHAR2(12);
    l_debit    VARCHAR2(34);
    l_credit   VARCHAR2(34);
    l_ref      VARCHAR2(64);
    l_id       NUMBER;
    l_amount   NUMBER;
    l_channel  VARCHAR2(24);
    l_reject   BOOLEAN;
    -- Self-transfers (the same account drawn for both legs) are skipped, so the number
    -- actually created is marginally below p_count. The ACTUAL count is what gets
    -- recorded and what the reconciliation in the results chapter must use; recording
    -- the requested count instead would silently corrupt every loss-rate calculation.
    l_created  NUMBER := 0;
  BEGIN
    load_pool;
    FOR i IN 1 .. p_count LOOP
      l_currency := rand_currency;
      l_segment  := rand_segment;
      l_debit    := pick_account(l_currency);
      l_credit   := pick_account(l_currency);
      CONTINUE WHEN l_debit IS NULL OR l_credit IS NULL OR l_debit = l_credit;

      l_ref := p_source || '-' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3') || '-' || i;

      l_amount  := rand_amount(l_segment, l_currency);
      l_channel := rand_channel;

      INSERT INTO TXN_A1 (TXN_REF, DEBIT_ACCOUNT, CREDIT_ACCOUNT, AMOUNT, CURRENCY,
                          STATUS, CHANNEL)
      VALUES (l_ref, l_debit, l_credit, l_amount, l_currency, 'INITIATED', l_channel)
      RETURNING TXN_ID INTO l_id;

      IF p_advance THEN
        l_reject := pct < PCT_REJECTED;
        UPDATE TXN_A1 SET STATUS = 'VALIDATED', UPDATED_AT = SYSTIMESTAMP,
                          VERSION = VERSION + 1
         WHERE TXN_ID = l_id;

        IF l_reject THEN
          UPDATE TXN_A1 SET STATUS = 'REJECTED', REJECT_CODE = 'AM' ||
                            LPAD(TRUNC(DBMS_RANDOM.VALUE(1, 20)), 2, '0'),
                            UPDATED_AT = SYSTIMESTAMP, VERSION = VERSION + 1
           WHERE TXN_ID = l_id;
        ELSE
          INSERT INTO LEDGER_ENTRY (TXN_ID, ACCOUNT_NO, DIRECTION, AMOUNT)
          VALUES (l_id, l_debit, 'D', l_amount);
          INSERT INTO LEDGER_ENTRY (TXN_ID, ACCOUNT_NO, DIRECTION, AMOUNT)
          VALUES (l_id, l_credit, 'C', l_amount);
          UPDATE TXN_A1 SET STATUS = 'PROCESSED', UPDATED_AT = SYSTIMESTAMP,
                            VERSION = VERSION + 1
           WHERE TXN_ID = l_id;
        END IF;
      END IF;

      l_created := l_created + 1;
      IF p_commit_every > 0 AND MOD(l_created, p_commit_every) = 0 THEN COMMIT; END IF;
    END LOOP;
    -- p_commit_every = 0 leaves everything in ONE transaction. That is deliberate: it is
    -- how fault case F5 (a transaction outstanding longer than Debezium's
    -- log.mining.transaction.retention.ms) is produced.
    COMMIT;

    UPDATE SYNTH_CONFIG SET TRANSACTIONS = TRANSACTIONS + l_created
     WHERE RUN_ID = (SELECT MAX(run_id) FROM SYNTH_CONFIG);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('generated ' || l_created || ' transactions from ' || p_source
                      || ' (' || (p_count - l_created) || ' skipped as self-transfers)');
  END generate_transactions;

  PROCEDURE reset_workload IS
  BEGIN
    -- Clears workload but PRESERVES reference data, so repeated experiment runs start
    -- from an identical account population without regenerating it.
    EXECUTE IMMEDIATE 'TRUNCATE TABLE LEDGER_ENTRY';
    DELETE FROM GROUND_TRUTH;
    DELETE FROM TXN_A1_EVT_SEQ;
    DELETE FROM A1_EVENT_OUTBOX;
    DELETE FROM TXN_A1;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('workload reset; reference data preserved');
  END reset_workload;

END PKG_SYNTH_DATA;
/

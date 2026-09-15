-- The credit process as it actually runs in an Uzbek bank.
--
-- Replaces the placeholder stage model. Two mechanics in this process cannot be represented at
-- all by a queue-and-work model, and they are the two that dominate elapsed time:
--
--   COMMITTEE — the credit committee sits once or twice a week. An application ready on Tuesday
--               afternoon does not wait "in a queue"; it waits for Thursday. That delay is
--               structural, and no amount of staff capacity or tooling shortens it. It is the
--               single most important thing a queue-based model gets wrong.
--
--   EXTERNAL  — collateral valuation is performed by a valuation company with a site visit, and
--               KBI / MIB / tax checks run against state systems. The bank is neither working
--               nor queuing; it is blocked on a third party. Reporting that as bank queue time
--               would credit the bank with a problem it cannot fix, and reporting it as customer
--               time would let it off one it can — by choosing a faster valuer.
--
-- Source: process description supplied by the thesis author, September 2026. Stage durations
-- remain ASSUMPTIONS calibrated to the ranges given there; they are not measurements.

-- Widen the type vocabulary before any stage uses the new values.
ALTER TABLE CREDIT_STAGE DROP CONSTRAINT CK_STAGE_TYPE;
ALTER TABLE CREDIT_STAGE ADD CONSTRAINT CK_STAGE_TYPE
  CHECK (STAGE_TYPE IN ('AUTOMATED','HUMAN','CUSTOMER','EXTERNAL','COMMITTEE'));

-- Product and collateral decide which path an application takes, so they belong on the case.
ALTER TABLE CREDIT_APPLICATION ADD (HAS_COLLATERAL NUMBER(1) DEFAULT 0 NOT NULL);

DELETE FROM CREDIT_STAGE_EVENT;
DELETE FROM CREDIT_APPLICATION;
DELETE FROM CREDIT_SYNTH_CONFIG;
DELETE FROM CREDIT_STAGE;
COMMIT;

--                          code                 seq  name                                        type         SLA (h)
INSERT INTO CREDIT_STAGE VALUES ('ARIZA_KIRITISH',    1,  'Ariza kiritish',                          'HUMAN',      0.5);
INSERT INTO CREDIT_STAGE VALUES ('HUJJAT_KUTISH',     2,  'Hujjatlar mijozdan kutilmoqda',           'CUSTOMER',   48);
INSERT INTO CREDIT_STAGE VALUES ('TASHQI_TEKSHIRUV',  3,  'Skoring, KBI, MIB, Soliq tekshiruvi',     'AUTOMATED',  0.5);
INSERT INTO CREDIT_STAGE VALUES ('GAROV_BAHOLASH',    4,  'Garov mulkini baholash',                  'EXTERNAL',   48);
INSERT INTO CREDIT_STAGE VALUES ('ANDERRAYTER',       5,  'Anderrayter tekshiruvi',                  'HUMAN',      40);
INSERT INTO CREDIT_STAGE VALUES ('QOMITA_KUTISH',     6,  'Kredit qo''mitasi yig''ilishini kutish',  'COMMITTEE',  72);
INSERT INTO CREDIT_STAGE VALUES ('QOMITA_QARORI',     7,  'Kredit qo''mitasi qarori',                'HUMAN',      2);
INSERT INTO CREDIT_STAGE VALUES ('SUGURTA_NOTARIUS',  8,  'Sug''urta va notarial taqiq',             'EXTERNAL',   8);
INSERT INTO CREDIT_STAGE VALUES ('SHARTNOMA',         9,  'Shartnoma va kafillik imzolash',          'CUSTOMER',   8);
INSERT INTO CREDIT_STAGE VALUES ('AJRATISH',          10, 'Kredit mablag''ini ajratish',             'HUMAN',      4);
INSERT INTO CREDIT_STAGE VALUES ('MONITORING',        11, 'Maqsadli ishlatilish monitoringi',        'HUMAN',      NULL);
INSERT INTO CREDIT_STAGE VALUES ('RAD_ETILDI',        97, 'Rad etildi',                              'AUTOMATED',  0.1);
INSERT INTO CREDIT_STAGE VALUES ('QAYTARILDI',        98, 'Qo''mita qayta ko''rib chiqishga qaytardi','HUMAN',     0.5);
INSERT INTO CREDIT_STAGE VALUES ('BEKOR_QILINDI',     99, 'Mijoz voz kechdi',                        'CUSTOMER',   0.1);
COMMIT;

-- When the credit committee sits. Held as data because it is the lever an operations team can
-- actually pull: adding a third sitting is a decision, not a technical change, and the analysis
-- should be able to show what it would be worth.
CREATE TABLE CREDIT_COMMITTEE_SCHEDULE (
  DAY_OF_WEEK  VARCHAR2(3) PRIMARY KEY,   -- English abbreviation, NLS-independent
  SITTING_HOUR NUMBER(4,2) NOT NULL
);
INSERT INTO CREDIT_COMMITTEE_SCHEDULE VALUES ('TUE', 14);
INSERT INTO CREDIT_COMMITTEE_SCHEDULE VALUES ('THU', 14);
COMMIT;

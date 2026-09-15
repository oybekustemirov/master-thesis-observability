-- A stage's type must describe what the case is WAITING FOR while it sits there, not what
-- produced it.
--
-- The first version typed DECISION as AUTOMATED because a system issues the decision. But the
-- time a case spends IN the DECISION stage is the applicant deciding whether to sign — 34.8 hours
-- at the median — and typing it AUTOMATED put 224 738 applicant-hours under "Bank: automated" in
-- the ownership split. The same error made DOCS_RECEIVED and SCORING look automated when a case
-- sitting in either is queued behind a person.
--
-- Retyped by the question that matters operationally: while the case is here, whose move is it?
UPDATE CREDIT_STAGE SET STAGE_TYPE = 'AUTOMATED' WHERE STAGE_CODE = 'SUBMITTED';
UPDATE CREDIT_STAGE SET STAGE_TYPE = 'CUSTOMER'  WHERE STAGE_CODE = 'DOCS_REQUESTED';
UPDATE CREDIT_STAGE SET STAGE_TYPE = 'HUMAN'     WHERE STAGE_CODE = 'DOCS_RECEIVED';
UPDATE CREDIT_STAGE SET STAGE_TYPE = 'AUTOMATED' WHERE STAGE_CODE = 'DOCS_VERIFIED';
UPDATE CREDIT_STAGE SET STAGE_TYPE = 'HUMAN'     WHERE STAGE_CODE = 'SCORING';
UPDATE CREDIT_STAGE SET STAGE_TYPE = 'AUTOMATED' WHERE STAGE_CODE = 'UNDERWRITING';
UPDATE CREDIT_STAGE SET STAGE_TYPE = 'CUSTOMER'  WHERE STAGE_CODE = 'DECISION';
UPDATE CREDIT_STAGE SET STAGE_TYPE = 'HUMAN'     WHERE STAGE_CODE = 'CONTRACT_SIGNED';
COMMIT;

-- Names follow the same rule: a stage is named for the state the case is in, so that a reader of
-- the results table is not told "Decision issued" for an interval in which nothing was decided.
UPDATE CREDIT_STAGE SET STAGE_NAME = 'Awaiting documents from applicant' WHERE STAGE_CODE = 'DOCS_REQUESTED';
UPDATE CREDIT_STAGE SET STAGE_NAME = 'Awaiting document verification'    WHERE STAGE_CODE = 'DOCS_RECEIVED';
UPDATE CREDIT_STAGE SET STAGE_NAME = 'Awaiting underwriter'              WHERE STAGE_CODE = 'SCORING';
UPDATE CREDIT_STAGE SET STAGE_NAME = 'Awaiting applicant signature'      WHERE STAGE_CODE = 'DECISION';
UPDATE CREDIT_STAGE SET STAGE_NAME = 'Awaiting disbursement'             WHERE STAGE_CODE = 'CONTRACT_SIGNED';
COMMIT;

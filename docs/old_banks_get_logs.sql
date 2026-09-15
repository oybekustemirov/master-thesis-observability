CREATE OR REPLACE PACKAGE BODY BRB_CREDIT_PROCESS_PKG IS

    PROCEDURE BRB_LOG_FIZ_INSERT(p_op_date IN DATE DEFAULT TRUNC(SYSDATE) - 1)
    AS
        v_rows_inserted NUMBER := 0;
        v_err_code      NUMBER;
        v_err_msg       VARCHAR2(4000);                                                                                                                                                                                                 BEGIN
DELETE FROM BRB_LOG_FIZ_PROCESS
WHERE TRUNC(last_event_time) = TRUNC(p_op_date);
INSERT INTO BRB_LOG_FIZ_PROCESS
(
    LOG_ID, LOAD_DATE,
    CLAIM_ID, POSITION, PRODUCT_ID, PROCESS_STAGE,
    LAST_EVENT_TIME, STATUS_STEP, USER_NAME, USER_ID,
    SALARY_USER_MIN, USER_JOB, FILIAL_ID, CLIENT_NAME,
    LOAN_SUMMA, LOAN_PROCENT, LOAN_PROCENT_SUM,
    LOAN_CODE, LOAN_NAME, EVENTS_COUNT
)
SELECT                                                                                                                                                                                                                                  BRB_LOG_FIZ_SEQ.NEXTVAL,
                                                                                                                                                                                                                                        SYSDATE,
                                                                                                                                                                                                                                        sq.CLAIM_ID, sq.POSITION, sq.PRODUCT_ID, sq.PROCESS_STAGE,
                                                                                                                                                                                                                                        sq.LAST_EVENT_TIME, sq.STATUS_STEP, sq.USER_NAME, sq.USER_ID,
                                                                                                                                                                                                                                        sq.SALARY_USER_MIN, sq.USER_JOB, sq.FILIAL_ID, sq.CLIENT_NAME,
                                                                                                                                                                                                                                        sq.LOAN_SUMMA, sq.LOAN_PROCENT, sq.LOAN_PROCENT_SUM,
                                                                                                                                                                                                                                        sq.LOAN_CODE, sq.LOAN_NAME, sq.EVENTS_COUNT
FROM
    (                                                                                                                                                                                                                                       WITH params AS (
        SELECT TRUNC(p_op_date) AS op_date FROM dual
    ),
                                                                                                                                                                                                                                                /* ====== 4 ta jadvaldan shu kundagi faollik + jismoniy shaxs filtri ====== */                                                                                                                                                      claims_in_range AS (
            -- ln_blanks_his da faollik
            SELECT DISTINCT b.claim_id
            FROM ln_blanks_his b
                     JOIN ln_claim lc ON lc.claim_id = b.claim_id
                AND lc.filial_code = 1037
                AND SUBSTR(lc.client_code, 1, 1) IN ('6', '9')
            WHERE b.filial_code = 1037
              AND b.modified_on >= (SELECT op_date FROM params)
              AND b.modified_on <  (SELECT op_date + 1 FROM params)
            UNION

            -- CRM kartalar da faollik
            SELECT DISTINCT c.claim_id
            FROM fbcrm_cc_claims_hs c
                     JOIN fbcrm_cc_cards_hs h ON h.cc_id = c.cc_id
                     JOIN ln_claim lc ON lc.claim_id = c.claim_id
                AND lc.filial_code = 1037
                AND SUBSTR(lc.client_code, 1, 1) IN ('6', '9')
            WHERE h.filial_code = 1037
              AND h.state_id != -1
                                                                                                                                                                                                                                                AND h.stage_id NOT IN (10, 60, 70)
                                                                                                                                                                                                                                                AND h.modified_on >= (SELECT op_date FROM params)
                                                                                                                                                                                                                                                AND h.modified_on <  (SELECT op_date + 1 FROM params)
                                                                                                                                                                                                                                            UNION

                                                                                                                                                                                                                                            -- CRM register da faollik
                                                                                                                                                                                                                                            SELECT DISTINCT c.claim_id
                                                                                                                                                                                                                                            FROM Fbcrm_Vf_Registers_Hs v
                                                                                                                                                                                                                                                JOIN fbcrm_cc_claims_hs c ON c.cc_id = v.cc_id
                                                                                                                                                                                                                                                JOIN Fbcrm_Vf_Reg_Protocols p
                                                                                                                                                                                                                                                ON p.Register_Id = v.Register_Id AND p.State_Id = v.State_Id
                                                                                                                                                                                                                                                JOIN ln_claim lc ON lc.claim_id = c.claim_id
                                                                                                                                                                                                                                                AND lc.filial_code = 1037
                                                                                                                                                                                                                                                AND SUBSTR(lc.client_code, 1, 1) IN ('6', '9')
                                                                                                                                                                                                                                            WHERE v.filial_code = 1037
                                                                                                                                                                                                                                              AND p.state_id <> 10
                                                                                                                                                                                                                                              AND p.modified_on >= (SELECT op_date FROM params)                                                                                                                                                                                   AND p.modified_on <  (SELECT op_date + 1 FROM params)

                                                                                                                                                                                                                                            UNION

                                                                                                                                                                                                                                            -- Tranzaksiyalarda faollik
                                                                                                                                                                                                                                            SELECT DISTINCT cl.claim_id
                                                                                                                                                                                                                                            FROM transacts_history t
                                                                                                                                                                                                                                                JOIN leads_history l ON l.id = t.lead_id AND l.code_filial = t.code_filial
                                                                                                                                                                                                                                                JOIN lead_protocol_hist p ON p.lead_id = l.id AND p.code_filial = l.code_filial
                                                                                                                                                                                                                                                JOIN ln_account n ON n.acc_id = t.acc_id
                                                                                                                                                                                                                                                AND n.filial_code = 1037
                                                                                                                                                                                                                                                AND n.loan_type_account = 1
                                                                                                                                                                                                                                                JOIN ln_claim cl ON cl.filial_code = 1037
                                                                                                                                                                                                                                                AND SUBSTR(cl.client_code, 1, 1) IN ('6', '9')
                                                                                                                                                                                                                                                AND BRB_REPORTS_PROCESS.Brb_Loan_Id(cl.client_code, cl.claim_id) = n.loan_id
                                                                                                                                                                                                                                            WHERE t.code_filial = 1037
                                                                                                                                                                                                                                              AND t.op_dc = 1
                                                                                                                                                                                                                                              AND p.code_emp != -7
                                                                                                                                                                                                                                              AND p.new_state_id IS NOT NULL
                                                                                                                                                                                                                                              AND p.time >= (SELECT op_date FROM params)
                                                                                                                                                                                                                                              AND p.time <  (SELECT op_date + 1 FROM params)
    ),
    claim_meta AS (
SELECT c.claim_id,
       c.product_id,                                                                                                                                                                                                                       c.client_code,
       c.claim_num,
       c.client_id,
       c.client_uid,
       c.summ_claim / 100 AS loan_summa,
       c.purpose_loan,
       BRB_REPORTS_PROCESS.Brb_Loan_Id(c.client_code, c.claim_id) AS client_loan_id,
       NVL(BRB_REPORTS_PROCESS.Brb_Credit_Procent(c.client_code, c.claim_num, c.product_id), 0) AS loan_procent,
       (c.summ_claim / 100) *
       NVL(BRB_REPORTS_PROCESS.Brb_Credit_Procent(c.client_code, c.claim_num, c.product_id), 0) / 100 / 365 AS loan_procent_sum,
       DECODE(c.currency, '000', 'Сум', Currency.Get_Name(c.currency)) AS code_val,
       BRB_REPORTS_PROCESS.Remove_Symbol(BRB_REPORTS_PROCESS.Brb_Cl_Name(c.claim_id)) AS client_name,
       BRB_REPORTS_PROCESS.Brb_Cl_Code(c.claim_id) AS client_code_text
FROM ln_claim c
         JOIN Ln_Security_Level l ON l.Client_Id = c.Client_Id
WHERE c.filial_code = 1037
  AND c.claim_id IN (SELECT claim_id FROM claims_in_range)
  AND c.parent_claim_id IS NULL
  AND c.claim_date >= TO_DATE('01.01.2025', 'DD.MM.YYYY')
  AND NVL(c.Product_Id, -1) = NVL((SELECT Ln_Init.Get_Module_Product_Id FROM Dual),
                                  NVL(c.Product_Id, -1))
  AND EXISTS (SELECT 1 FROM Ln_Blanks b WHERE b.Claim_Id = c.Claim_Id
                                          AND b.Grace_Period IS NOT NULL)
    ),
                                                                                                                                                                                                                                                         claim_branch AS (
                                                                                                                                                                                                                                                             SELECT claim_id, MAX(branch_id) AS branch_id
                                                                                                                                                                                                                                                             FROM ln_blanks_his
                                                                                                                                                                                                                                                             WHERE claim_id IN (SELECT claim_id FROM claims_in_range)                                                                                                                                                                            GROUP BY claim_id
                                                                                                                                                                                                                                                         ),

                                                                                                                                                                                                                                                         claim_timing AS (                                                                                                                                                                                                                       SELECT claim_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        MIN(created_on) AS base_op_begin,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        MAX(modified_on) AS base_last_modified,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        MAX(loan_line_purpose) KEEP(DENSE_RANK LAST ORDER BY modified_on) AS latest_loan_purpose
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 FROM ln_blanks_his                                                                                                                                                                                                                 WHERE claim_id IN (SELECT claim_id FROM claims_in_range)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 GROUP BY claim_id
                                                                                                                                                                                                                                                         ),

                                                                                                                                                                                                                                                         claim_full AS (                                                                                                                                                                                                                         SELECT cm.claim_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cm.product_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cm.client_code,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cm.claim_num,                                                                                                                                                                                                                       cm.client_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cm.client_uid,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cm.loan_summa,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cm.loan_procent,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cm.loan_procent_sum,                                                                                                                                                                                                                cm.purpose_loan AS loan_code,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        NVL(ct.latest_loan_purpose, cm.purpose_loan) AS loan_name,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cm.code_val,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cm.client_loan_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cm.client_name,                                                                                                                                                                                                                     cm.client_code_text,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cb.branch_id AS filial_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        (SELECT q.name_uz
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         FROM qqb_bank_name_uz q
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         WHERE q.branch_id = cb.branch_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           AND ROWNUM = 1) AS filial_name,                                                                                                                                                                                                 ct.base_op_begin,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ct.base_last_modified
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 FROM claim_meta cm                                                                                                                                                                                                                  JOIN claim_branch cb ON cb.claim_id = cm.claim_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     JOIN claim_timing ct ON ct.claim_id = cm.claim_id
                                                                                                                                                                                                                                                         ),
                                                                                                                                                                                                                                                         sud_accounts AS (
                                                                                                                                                                                                                                                             SELECT cf.claim_id,
                                                                                                                                                                                                                                                                    (SELECT SUBSTR(n.account_code, -20)
                                                                                                                                                                                                                                                                     FROM ln_account n                                                                                                                                                                                                                  WHERE n.filial_code = 1037
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          AND n.loan_id = cf.client_loan_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          AND n.loan_type_account = 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          AND ROWNUM = 1) AS client_sud_acc,
                                                                                                                                                                                                                                                                    (SELECT n.acc_id                                                                                                                                                                                                                       FROM ln_account n
                                                                                                                                                                                                                                                                     WHERE n.filial_code = 1037
                                                                                                                                                                                                                                                                       AND n.loan_id = cf.client_loan_id                                                                                                                                                                                                   AND n.loan_type_account = 1
                                                                                                                                                                                                                                                                       AND ROWNUM = 1) AS sud_acc_id
                                                                                                                                                                                                                                                             FROM claim_full cf                                                                                                                                                                                                            ),

                                                                                                                                                                                                                                                         base_hist AS (
                                                                                                                                                                                                                                                             SELECT b.claim_id,
                                                                                                                                                                                                                                                                    b.action_id,                                                                                                                                                                                                                        b.prev_level_id,
                                                                                                                                                                                                                                                                    b.level_id,
                                                                                                                                                                                                                                                                    b.stage_id,
                                                                                                                                                                                                                                                                    b.state_id,                                                                                                                                                                                                                         b.prev_user_id,
                                                                                                                                                                                                                                                                    b.modified_by,
                                                                                                                                                                                                                                                                    b.created_on,                                                                                                                                                                                                                       b.modified_on,
                                                                                                                                                                                                                                                                    b.loan_line_purpose,
                                                                                                                                                                                                                                                                    b.branch_id,
                                                                                                                                                                                                                                                                    b.filial_code,
                                                                                                                                                                                                                                                                    cf.product_id,                                                                                                                                                                                                                      cf.loan_summa,
                                                                                                                                                                                                                                                                    cf.loan_procent,
                                                                                                                                                                                                                                                                    cf.loan_procent_sum,                                                                                                                                                                                                                cf.loan_code,
                                                                                                                                                                                                                                                                    cf.code_val,
                                                                                                                                                                                                                                                                    cf.client_name,
                                                                                                                                                                                                                                                                    cf.claim_num,                                                                                                                                                                                                                       cf.client_code_text,
                                                                                                                                                                                                                                                                    cf.client_id,
                                                                                                                                                                                                                                                                    cf.client_uid,
                                                                                                                                                                                                                                                                    sa.client_sud_acc,
                                                                                                                                                                                                                                                                    sa.sud_acc_id,                                                                                                                                                                                                                      cf.client_loan_id,
                                                                                                                                                                                                                                                                    cf.base_op_begin,
                                                                                                                                                                                                                                                                    (SELECT l.name_text
                                                                                                                                                                                                                                                                     FROM brb_ln_s_blank_levels_v l
                                                                                                                                                                                                                                                                     WHERE l.level_id = b.prev_level_id) AS prev_level_name,
                                                                                                                                                                                                                                                                    CASE                                                                                                                                                                                                                                  WHEN b.action_id = 0
                                                                                                                                                                                                                                                                        AND ROW_NUMBER() OVER(PARTITION BY b.claim_id ORDER BY b.modified_on) != 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              THEN (SELECT mlm.cur_nls(a.name) FROM ln_s_blank_actions a WHERE a.action_id = 1)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          ELSE (SELECT mlm.cur_nls(a.name) FROM ln_s_blank_actions a WHERE a.action_id = b.action_id)
                                                                                                                                                                                                                                                                        END AS action_name
                                                                                                                                                                                                                                                             FROM ln_blanks_his b                                                                                                                                                                                                                JOIN claim_full cf ON cf.claim_id = b.claim_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 LEFT JOIN sud_accounts sa ON sa.claim_id = b.claim_id
                                                                                                                                                                                                                                                             WHERE b.filial_code = 1037
                                                                                                                                                                                                                                                               AND b.claim_id IN (SELECT claim_id FROM claims_in_range)
                                                                                                                                                                                                                                                               AND NOT (b.action_id = 1 AND b.prev_level_id IS NULL AND b.modified_by = -7)        /* +YANGI: tizim "Изменить" larni chiqarish */
                                                                                                                                                                                                                                                         ),
                                                                                                                                                                                                                                                         hist_with_neighbors AS (                                                                                                                                                                                                                SELECT bh.*,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        LAG(bh.prev_level_name)  OVER(PARTITION BY bh.claim_id ORDER BY bh.modified_on) AS prev_level_name_prev_row,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        LEAD(bh.prev_level_name) OVER(PARTITION BY bh.claim_id ORDER BY bh.modified_on) AS prev_level_name_next_row
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 FROM base_hist bh                                                                                                                                                                                                             ),

                                                                                                                                                                                                                                                         base_events AS (
                                                                                                                                                                                                                                                             SELECT x.claim_id,
                                                                                                                                                                                                                                                                    x.prev_level_name AS position,
                                                                                                                                                                                                                                                                    x.product_id,
                                                                                                                                                                                                                                                                    CASE                                                                                                                                                                                                                                  WHEN NVL(x.prev_level_id, -1) = -1 THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              x.prev_level_name || ' ' || x.action_name
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          WHEN x.action_id = 4 THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              x.prev_level_name || ' ' || x.action_name || ' ' || x.prev_level_name_prev_row
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          WHEN x.action_id = 3 THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              x.prev_level_name || ' ' || x.action_name || ' ' || x.prev_level_name_next_row                                                                                                                                                    ELSE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              x.prev_level_name || ' ' || x.action_name
                                                                                                                                                                                                                                                                        END AS process_stage,                                                                                                                                                                                                               CASE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN x.prev_level_id = 5 AND x.level_id = 7 AND x.state_id = 4 AND x.action_id = 3
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    THEN 'Отправлен'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ELSE BRB_REPORTS_PROCESS.Brb_State_Name(x.state_id)
                                                                                                                                                                                                                                                                        END AS status_step,
                                                                                                                                                                                                                                                                    NVL(x.prev_user_id, x.modified_by) AS user_id,
                                                                                                                                                                                                                                                                    CASE
                                                                                                                                                                                                                                                                        WHEN x.prev_user_id IS NULL
                                                                                                                                                                                                                                                                            THEN BRB_REPORTS_PROCESS.Remove_Symbol(BRB_REPORTS_PROCESS.Brb_User_Name(x.modified_by))
                                                                                                                                                                                                                                                                        ELSE BRB_REPORTS_PROCESS.Remove_Symbol(BRB_REPORTS_PROCESS.Brb_User_Name(x.prev_user_id))
                                                                                                                                                                                                                                                                        END AS user_name,
                                                                                                                                                                                                                                                                    BRB_REPORTS_PROCESS.Remove_Symbol(BRB_REPORTS_PROCESS.Brb_User_Name(x.prev_user_id)) AS prev_user_name,
                                                                                                                                                                                                                                                                    NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(x.modified_on), x.modified_by),
                                                                                                                                                                                                                                                                        BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(x.modified_on), x.modified_by)) AS salary_user,
                                                                                                                                                                                                                                                                    NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(x.modified_on), x.modified_by),
                                                                                                                                                                                                                                                                        BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(x.modified_on), x.modified_by)) * 1.12 AS salary_user_tax,
                                                                                                                                                                                                                                                                    CASE
                                                                                                                                                                                                                                                                        WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(x.modified_on), x.modified_by) = 0
                                                                                                                                                                                                                                                                            THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(x.modified_on), x.modified_by)
                                                                                                                                                                                                                                                                        ELSE (NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(x.modified_on), x.modified_by), 0) * 1.12) /
                                                                                                                                                                                                                                                                             BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(x.modified_on), x.modified_by)
                                                                                                                                                                                                                                                                        END AS salary_user_month,
                                                                                                                                                                                                                                                                    CASE
                                                                                                                                                                                                                                                                        WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(x.modified_on), x.modified_by) = 0
                                                                                                                                                                                                                                                                            THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(x.modified_on), x.modified_by) / (8 * 60 * 21)
                                                                                                                                                                                                                                                                        ELSE ((NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(x.modified_on), x.modified_by), 0) * 1.12) /
                                                                                                                                                                                                                                                                              BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(x.modified_on), x.modified_by)) / (8 * 60 * 21)
                                                                                                                                                                                                                                                                        END AS salary_user_min,
                                                                                                                                                                                                                                                                    NVL(BRB_REPORTS_PROCESS.Brb_Level_Name(x.prev_level_id),
                                                                                                                                                                                                                                                                        BRB_REPORTS_PROCESS.Brb_Level_Name(x.level_id)) AS user_job,
                                                                                                                                                                                                                                                                    x.created_on  AS user_op_begin,
                                                                                                                                                                                                                                                                    x.modified_on AS user_op_end,                                                                                                                                                                                                       x.loan_summa,
                                                                                                                                                                                                                                                                    x.loan_procent,
                                                                                                                                                                                                                                                                    x.loan_procent_sum,                                                                                                                                                                                                                 x.loan_code,
                                                                                                                                                                                                                                                                    x.loan_line_purpose AS loan_name,
                                                                                                                                                                                                                                                                    x.code_val,
                                                                                                                                                                                                                                                                    x.branch_id AS filial_id,
                                                                                                                                                                                                                                                                    (SELECT q.name_uz FROM qqb_bank_name_uz q WHERE q.branch_id = x.branch_id AND ROWNUM = 1) AS filial_name,
                                                                                                                                                                                                                                                                    x.client_name,
                                                                                                                                                                                                                                                                    x.modified_on AS modified_on,
                                                                                                                                                                                                                                                                    DECODE(x.stage_id, 1, '1 этап', '2 этап', 'N/A') AS stage_name,
                                                                                                                                                                                                                                                                    x.claim_num,
                                                                                                                                                                                                                                                                    x.client_code_text AS client_code,                                                                                                                                                                                                  x.client_id,
                                                                                                                                                                                                                                                                    x.client_uid,
                                                                                                                                                                                                                                                                    x.client_sud_acc,
                                                                                                                                                                                                                                                                    x.sud_acc_id,                                                                                                                                                                                                                       x.client_loan_id,
                                                                                                                                                                                                                                                                    x.modified_on AS event_time
                                                                                                                                                                                                                                                             FROM hist_with_neighbors x                                                                                                                                                                                                         WHERE x.modified_on >= (SELECT op_date FROM params)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  AND x.modified_on <  (SELECT op_date + 1 FROM params)
                                                                                                                                                                                                                                                         ),
                                                                                                                                                                                                                                                         trans_events AS (
                                                                                                                                                                                                                                                             SELECT cf.claim_id,
                                                                                                                                                                                                                                                                    CAST(NULL AS VARCHAR2(200)) AS position,
                                                                                                                                                                                                                                                                    cf.product_id,                                                                                                                                                                                                                      CASE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            WHEN p.new_state_id = 41 AND p.code_emp = -7 THEN '(Администратор IABS провёл)'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            WHEN p.new_state_id = 11 THEN 'Перевод сформирован'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            WHEN p.new_state_id IN (41, 50, 32) THEN 'Перевод подтверждён'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            WHEN p.new_state_id IN (21) THEN 'Перевод возвращён'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ELSE NVL(BRB_REPORTS_PROCESS.Remove_Symbol(p.description), 'Транзакция-' || p.new_state_id)
                                                                                                                                                                                                                                                                        END AS process_stage,                                                                                                                                                                                                               CASE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN p.new_state_id = 41 AND p.code_emp = -7 THEN 'Проведен'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN p.new_state_id = 11 THEN 'Введен'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN p.new_state_id IN (41, 50) THEN 'Бош Хисobchi Утв.ГлБ и Отправил в КТЦ'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ELSE BRB_REPORTS_PROCESS.Brb_State_Name(p.new_state_id)
                                                                                                                                                                                                                                                                        END AS status_step,                                                                                                                                                                                                                 p.code_emp AS user_id,
                                                                                                                                                                                                                                                                    BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(p.code_emp)) AS user_name,
                                                                                                                                                                                                                                                                    BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(p.code_emp)) AS prev_user_name,
                                                                                                                                                                                                                                                                    NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.time), p.code_emp),
                                                                                                                                                                                                                                                                        BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(p.time), p.code_emp)) AS salary_user,
                                                                                                                                                                                                                                                                    NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.time), p.code_emp),
                                                                                                                                                                                                                                                                        BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(p.time), p.code_emp)) * 1.12 AS salary_user_tax,
                                                                                                                                                                                                                                                                    CASE
                                                                                                                                                                                                                                                                        WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.time), p.code_emp) = 0
                                                                                                                                                                                                                                                                            THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(p.time), p.code_emp)
                                                                                                                                                                                                                                                                        ELSE (NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.time), p.code_emp), 0) * 1.12) /
                                                                                                                                                                                                                                                                             BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.time), p.code_emp)
                                                                                                                                                                                                                                                                        END AS salary_user_month,                                                                                                                                                                                                           CASE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.time), p.code_emp) = 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(p.time), p.code_emp) / (8 * 60 * 21)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ELSE ((NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.time), p.code_emp), 0) * 1.12) /
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.time), p.code_emp)) / (8 * 60 * 21)
                                                                                                                                                                                                                                                                        END AS salary_user_min,
                                                                                                                                                                                                                                                                    BRB_REPORTS_PROCESS.Brb_Post_Name(p.code_emp) AS user_job,
                                                                                                                                                                                                                                                                    cf.base_op_begin AS user_op_begin,
                                                                                                                                                                                                                                                                    p.time AS user_op_end,
                                                                                                                                                                                                                                                                    cf.loan_summa,                                                                                                                                                                                                                      cf.loan_procent,
                                                                                                                                                                                                                                                                    cf.loan_procent_sum,
                                                                                                                                                                                                                                                                    cf.loan_code,
                                                                                                                                                                                                                                                                    cf.loan_name,                                                                                                                                                                                                                       cf.code_val,
                                                                                                                                                                                                                                                                    cf.filial_id,
                                                                                                                                                                                                                                                                    cf.filial_name,
                                                                                                                                                                                                                                                                    cf.client_name,
                                                                                                                                                                                                                                                                    p.time AS modified_on,
                                                                                                                                                                                                                                                                    'Transact-' || p.new_state_id AS stage_name,
                                                                                                                                                                                                                                                                    cf.claim_num,                                                                                                                                                                                                                       cf.client_code_text AS client_code,
                                                                                                                                                                                                                                                                    cf.client_id,
                                                                                                                                                                                                                                                                    cf.client_uid,
                                                                                                                                                                                                                                                                    sa.client_sud_acc,
                                                                                                                                                                                                                                                                    sa.sud_acc_id,                                                                                                                                                                                                                      cf.client_loan_id,
                                                                                                                                                                                                                                                                    p.time AS event_time
                                                                                                                                                                                                                                                             FROM transacts_history t
                                                                                                                                                                                                                                                                      JOIN leads_history l
                                                                                                                                                                                                                                                                           ON l.id = t.lead_id AND l.code_filial = t.code_filial
                                                                                                                                                                                                                                                                      JOIN lead_protocol_hist p
                                                                                                                                                                                                                                                                           ON p.lead_id = l.id AND p.code_filial = l.code_filial
                                                                                                                                                                                                                                                                      JOIN sud_accounts sa ON sa.sud_acc_id = t.acc_id
                                                                                                                                                                                                                                                                      JOIN claim_full cf ON cf.claim_id = sa.claim_id
                                                                                                                                                                                                                                                             WHERE t.code_filial = 1037
                                                                                                                                                                                                                                                               AND p.code_emp != -7
                                                                                                                                                                                                                                                               AND p.new_state_id IS NOT NULL
                                                                                                                                                                                                                                                               AND t.op_dc = 1
                                                                                                                                                                                                                                                               AND p.time >= (SELECT op_date FROM params)                                                                                                                                                                                          AND p.time <  (SELECT op_date + 1 FROM params)
                                                                                                                                                                                                                                                         ),

                                                                                                                                                                                                                                                         crm_card_history AS (
                                                                                                                                                                                                                                                             SELECT h.cc_id,
                                                                                                                                                                                                                                                                    h.stage_id,                                                                                                                                                                                                                         MAX(h.state_id) AS state_id,
                                                                                                                                                                                                                                                                    MAX(h.modified_by) AS modified_by,
                                                                                                                                                                                                                                                                    MAX(h.modified_on) AS modified_on
                                                                                                                                                                                                                                                             FROM fbcrm_cc_cards_hs h
                                                                                                                                                                                                                                                                      JOIN fbcrm_cc_claims_hs c ON c.cc_id = h.cc_id
                                                                                                                                                                                                                                                             WHERE h.filial_code = 1037
                                                                                                                                                                                                                                                               AND c.claim_id IN (SELECT claim_id FROM claims_in_range)
                                                                                                                                                                                                                                                               AND h.state_id != -1
                                                                                                                                                                                                                                                               AND h.stage_id NOT IN (10, 60, 70)
                                                                                                                                                                                                                                                               AND h.modified_on >= (SELECT op_date FROM params)
                                                                                                                                                                                                                                                               AND h.modified_on <  (SELECT op_date + 1 FROM params)
                                                                                                                                                                                                                                                             GROUP BY h.cc_id, h.stage_id                                                                                                                                                                                                   ),

                                                                                                                                                                                                                                                         crm_card_events AS (
                                                                                                                                                                                                                                                             SELECT cf.claim_id,
                                                                                                                                                                                                                                                                    (SELECT CASE WHEN h.Dep_Parent_Code IN ('012108') THEN 'Андеррайтер' ELSE '' END
                                                                                                                                                                                                                                                                     FROM hr_emps_v h
                                                                                                                                                                                                                                                                     WHERE h.Emp_Id IN (SELECT q.pers_id FROM core_users q WHERE q.user_id = crm.modified_by)) AS position,
                                                                                                                                                                                                                                                                    cf.product_id,
                                                                                                                                                                                                                                                                    DECODE(crm.stage_id,
                                                                                                                                                                                                                                                                           '20', 'Подбор продукта',
                                                                                                                                                                                                                                                                           '30', 'Кредитная анкета',
                                                                                                                                                                                                                                                                           '40', 'Ввод Обеспечения',
                                                                                                                                                                                                                                                                           '50', 'Расчет Скоринга',
                                                                                                                                                                                                                                                                           '1',  'Менеджер андеррайтерга жунатди',
                                                                                                                                                                                                                                                                           'CRM-' || crm.stage_id) AS process_stage,
                                                                                                                                                                                                                                                                    NVL(state.name, 'CRM-' || crm.state_id) AS status_step,
                                                                                                                                                                                                                                                                    crm.modified_by AS user_id,
                                                                                                                                                                                                                                                                    BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(crm.modified_by)) AS user_name,
                                                                                                                                                                                                                                                                    BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(crm.modified_by)) AS prev_user_name,
                                                                                                                                                                                                                                                                    NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(crm.modified_on), crm.modified_by),
                                                                                                                                                                                                                                                                        BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(crm.modified_on), crm.modified_by)) AS salary_user,
                                                                                                                                                                                                                                                                    NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(crm.modified_on), crm.modified_by),
                                                                                                                                                                                                                                                                        BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(crm.modified_on), crm.modified_by)) * 1.12 AS salary_user_tax,
                                                                                                                                                                                                                                                                    CASE
                                                                                                                                                                                                                                                                        WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(crm.modified_on), crm.modified_by) = 0
                                                                                                                                                                                                                                                                            THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(crm.modified_on), crm.modified_by)
                                                                                                                                                                                                                                                                        ELSE (NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(crm.modified_on), crm.modified_by), 0) * 1.12) /
                                                                                                                                                                                                                                                                             BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(crm.modified_on), crm.modified_by)
                                                                                                                                                                                                                                                                        END AS salary_user_month,
                                                                                                                                                                                                                                                                    CASE
                                                                                                                                                                                                                                                                        WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(crm.modified_on), crm.modified_by) = 0
                                                                                                                                                                                                                                                                            THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(crm.modified_on), crm.modified_by) / (8 * 60 * 21)
                                                                                                                                                                                                                                                                        ELSE ((NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(crm.modified_on), crm.modified_by), 0) * 1.12) /
                                                                                                                                                                                                                                                                              BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(crm.modified_on), crm.modified_by)) / (8 * 60 * 21)
                                                                                                                                                                                                                                                                        END AS salary_user_min,
                                                                                                                                                                                                                                                                    BRB_REPORTS_PROCESS.Brb_Post_Name(crm.modified_by) AS user_job,
                                                                                                                                                                                                                                                                    cf.base_op_begin AS user_op_begin,                                                                                                                                                                                                  crm.modified_on AS user_op_end,
                                                                                                                                                                                                                                                                    cf.loan_summa,
                                                                                                                                                                                                                                                                    cf.loan_procent,
                                                                                                                                                                                                                                                                    cf.loan_procent_sum,                                                                                                                                                                                                                cf.loan_code,
                                                                                                                                                                                                                                                                    cf.loan_name,
                                                                                                                                                                                                                                                                    cf.code_val,
                                                                                                                                                                                                                                                                    cf.filial_id,
                                                                                                                                                                                                                                                                    cf.filial_name,                                                                                                                                                                                                                     cf.client_name,
                                                                                                                                                                                                                                                                    crm.modified_on AS modified_on,
                                                                                                                                                                                                                                                                    'CRM-' || crm.stage_id AS stage_name,
                                                                                                                                                                                                                                                                    cf.claim_num,                                                                                                                                                                                                                       cf.client_code_text AS client_code,
                                                                                                                                                                                                                                                                    cf.client_id,
                                                                                                                                                                                                                                                                    cf.client_uid,
                                                                                                                                                                                                                                                                    sa.client_sud_acc,                                                                                                                                                                                                                  sa.sud_acc_id,
                                                                                                                                                                                                                                                                    cf.client_loan_id,
                                                                                                                                                                                                                                                                    crm.modified_on AS event_time
                                                                                                                                                                                                                                                             FROM crm_card_history crm
                                                                                                                                                                                                                                                                      JOIN fbcrm_cc_claims_hs c ON c.cc_id = crm.cc_id
                                                                                                                                                                                                                                                                      JOIN claim_full cf ON cf.claim_id = c.claim_id
                                                                                                                                                                                                                                                                      JOIN sud_accounts sa ON sa.claim_id = cf.claim_id
                                                                                                                                                                                                                                                                      LEFT JOIN Fbcrm_Cc_r_States_v state ON state.state_id = crm.state_id
                                                                                                                                                                                                                                                             WHERE crm.state_id NOT IN (10, 60, 70)
                                                                                                                                                                                                                                                               AND crm.stage_id NOT IN (60, 70)                                                                                                                                                                                             ),

                                                                                                                                                                                                                                                         crm_register_events AS (                                                                                                                                                                                                                SELECT cf.claim_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        (SELECT CASE WHEN h.Dep_Parent_Code IN ('012108') THEN 'Андеррайтер' ELSE '' END
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         FROM hr_emps_v h
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         WHERE h.Emp_Id IN (SELECT q.pers_id FROM core_users q WHERE q.user_id = p.modified_by)) AS position,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.product_id,                                                                                                                                                                                                                      CASE p.state_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN 1 THEN 'Менеджер отправил заявку андеррайтеру'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN 2 THEN 'Андеррайтер вернул заявку в исходное состояние'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN 3 THEN 'Руководитель андеррайтеров перераспределил заявку'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN 4 THEN 'Руководитель андеррайтеров перераспределил заявку'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN 5 THEN 'Андеррайтер принял заявку'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN 6 THEN 'Андеррайтер одобрил заявку'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN 7 THEN 'Андеррайтер отклонил заявку'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHEN 8 THEN 'Менеджер принял заявку на повторную обработку'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ELSE BRB_REPORTS_PROCESS.Remove_Symbol(p.Action_Text)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            END AS process_stage,                                                                                                                                                                                                               DECODE(p.state_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       1, 'Введен',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       3, 'Распределил',                                                                                                                                                                                                                   5, 'Принял',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       6, 'Утвердиль',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       7, 'Отклонил',                                                                                                                                                                                                                      8, 'Отправиль',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       'CRM-Регист' || p.state_id) AS status_step,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        p.modified_by AS user_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(p.modified_by)) AS user_name,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(p.modified_by)) AS prev_user_name,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.modified_on), p.modified_by),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(p.modified_on), p.modified_by)) AS salary_user,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.modified_on), p.modified_by),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(p.modified_on), p.modified_by)) * 1.12 AS salary_user_tax,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        CASE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.modified_on), p.modified_by) = 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(p.modified_on), p.modified_by)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ELSE (NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.modified_on), p.modified_by), 0) * 1.12) /
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.modified_on), p.modified_by)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            END AS salary_user_month,                                                                                                                                                                                                           CASE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.modified_on), p.modified_by) = 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(p.modified_on), p.modified_by) / (8 * 60 * 21)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ELSE ((NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.modified_on), p.modified_by), 0) * 1.12) /
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.modified_on), p.modified_by)) / (8 * 60 * 21)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            END AS salary_user_min,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        BRB_REPORTS_PROCESS.Brb_Post_Name(p.modified_by) AS user_job,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.base_op_begin AS user_op_begin,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        p.modified_on AS user_op_end,                                                                                                                                                                                                       cf.loan_summa,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.loan_procent,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.loan_procent_sum,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.loan_code,                                                                                                                                                                                                                       cf.loan_name,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.code_val,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.filial_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.filial_name,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.client_name,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        p.modified_on AS modified_on,                                                                                                                                                                                                       'CRM-Reg-' || p.state_id AS stage_name,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.claim_num,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.client_code_text AS client_code,                                                                                                                                                                                                 cf.client_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.client_uid,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        sa.client_sud_acc,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        sa.sud_acc_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        cf.client_loan_id,                                                                                                                                                                                                                  p.modified_on AS event_time
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 FROM Fbcrm_Vf_Registers_Hs v
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          JOIN fbcrm_cc_claims_hs c ON c.cc_id = v.cc_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          JOIN Fbcrm_Vf_Reg_Protocols p
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               ON p.Register_Id = v.Register_Id AND p.State_Id = v.State_Id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          JOIN claim_full cf ON cf.claim_id = c.claim_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          JOIN sud_accounts sa ON sa.claim_id = cf.claim_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 WHERE v.filial_code = 1037
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   AND c.claim_id IN (SELECT claim_id FROM claims_in_range)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   AND p.state_id <> 10
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   AND p.modified_on >= (SELECT op_date FROM params)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   AND p.modified_on <  (SELECT op_date + 1 FROM params)                                                                                                                                                                        ),

                                                                                                                                                                                                                                                         all_events AS (                                                                                                                                                                                                                         SELECT * FROM base_events
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 UNION ALL
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 SELECT * FROM trans_events
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 UNION ALL
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 SELECT * FROM crm_card_events                                                                                                                                                                                                       UNION ALL
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 SELECT * FROM crm_register_events
                                                                                                                                                                                                                                                         )
SELECT claim_id,
       NVL(TRIM(position), 'Менеджер') AS position,
                                                                                                                                                                                                                                                           product_id,                                                                                                                                                                                                                         CASE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   WHEN TRIM(process_stage) = 'Заявка поступила в "Общий реестр"'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       THEN 'Менеджер направил заявку андеррайтеру'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   ELSE TRIM(process_stage)
END AS process_stage,                                                                                                                                                                                                               event_time AS last_event_time,
                                                                                                                                                                                                                                                           status_step,
                                                                                                                                                                                                                                                           user_name,
                                                                                                                                                                                                                                                           user_id,
                                                                                                                                                                                                                                                           NVL(ROUND(salary_user_min), 1000) AS salary_user_min,
                                                                                                                                                                                                                                                           user_job,                                                                                                                                                                                                                           filial_id,
                                                                                                                                                                                                                                                           client_name,
                                                                                                                                                                                                                                                           loan_summa,
                                                                                                                                                                                                                                                           loan_procent,
                                                                                                                                                                                                                                                           loan_procent_sum,
                                                                                                                                                                                                                                                           loan_code,                                                                                                                                                                                                                          loan_name,
                                                                                                                                                                                                                                                           COUNT(*) AS events_count
                                                                                                                                                                                                                                                    FROM all_events
                                                                                                                                                                                                                                                    GROUP BY claim_id,
                                                                                                                                                                                                                                                             NVL(TRIM(position), 'Менеджер'),                                                                                                                                                                                                    product_id,
                                                                                                                                                                                                                                                             TRIM(process_stage),
                                                                                                                                                                                                                                                             status_step,                                                                                                                                                                                                                        user_name,
                                                                                                                                                                                                                                                             user_id,
                                                                                                                                                                                                                                                             NVL(ROUND(salary_user_min), 1000),
                                                                                                                                                                                                                                                             user_job,
                                                                                                                                                                                                                                                             filial_id,
                                                                                                                                                                                                                                                             client_name,                                                                                                                                                                                                                        loan_summa,
                                                                                                                                                                                                                                                             loan_procent,
                                                                                                                                                                                                                                                             loan_procent_sum,
                                                                                                                                                                                                                                                             loan_code,
                                                                                                                                                                                                                                                             loan_name,
                                                                                                                                                                                                                                                             event_time
            ) sq;

        v_rows_inserted := SQL%ROWCOUNT;                                                                                                                                                                                                    COMMIT;

DBMS_OUTPUT.PUT_LINE(
                'BRB_LOG_FIZ_INSERT: ' || v_rows_inserted ||
                ' qator yuklandi. Sana: ' || TO_CHAR(p_op_date, 'DD.MM.YYYY')
        );
EXCEPTION                                                                                                                                                                                                                               WHEN OTHERS THEN
            ROLLBACK;
            v_err_code := SQLCODE;
            v_err_msg  := SQLERRM;                                                                                                                                                                                                              RAISE_APPLICATION_ERROR(
                    -20001,
                    'BRB_LOG_FIZ_INSERT xatosi [' ||
                    TO_CHAR(p_op_date, 'DD.MM.YYYY') || ']: ' ||
                    v_err_code || ' - ' || SUBSTR(v_err_msg, 1, 3500)
                                                                                                                                                                                                                                                );                                                                                                                                                                                                                          END BRB_LOG_FIZ_INSERT;


    PROCEDURE BRB_LOG_FIZ_INSERT_last(p_op_date IN DATE DEFAULT TRUNC(SYSDATE) - 1)                                                                                                                                                          AS
        v_rows_inserted NUMBER := 0;
        v_err_code      NUMBER;
        v_err_msg       VARCHAR2(4000);
BEGIN
DELETE FROM BRB_LOG_FIZ_PROCESS
WHERE TRUNC(last_event_time) = TRUNC(p_op_date);

INSERT INTO BRB_LOG_FIZ_PROCESS
(
    LOG_ID, LOAD_DATE,
    CLAIM_ID, POSITION, PRODUCT_ID, PROCESS_STAGE,
    LAST_EVENT_TIME, STATUS_STEP, USER_NAME, USER_ID,
    SALARY_USER_MIN, USER_JOB, FILIAL_ID, CLIENT_NAME,
    LOAN_SUMMA, LOAN_PROCENT, LOAN_PROCENT_SUM,
    LOAN_CODE, LOAN_NAME, EVENTS_COUNT
)
SELECT
    BRB_LOG_FIZ_SEQ.NEXTVAL,
    SYSDATE,
    sq.CLAIM_ID, sq.POSITION, sq.PRODUCT_ID, sq.PROCESS_STAGE,
    sq.LAST_EVENT_TIME, sq.STATUS_STEP, sq.USER_NAME, sq.USER_ID,
    sq.SALARY_USER_MIN, sq.USER_JOB, sq.FILIAL_ID, sq.CLIENT_NAME,
    sq.LOAN_SUMMA, sq.LOAN_PROCENT, sq.LOAN_PROCENT_SUM,
    sq.LOAN_CODE, sq.LOAN_NAME, sq.EVENTS_COUNT
FROM
    (
        WITH params AS (
            SELECT TRUNC(p_op_date) AS op_date FROM dual
        ),

            /* ====== 4 ta jadvaldan shu kundagi faollik + jismoniy shaxs filtri ====== */
             claims_in_range AS (
                 -- ln_blanks_his da faollik
                 SELECT DISTINCT b.claim_id
                 FROM ln_blanks_his b
                          JOIN ln_claim lc ON lc.claim_id = b.claim_id
                     AND lc.filial_code = 1037
                     AND SUBSTR(lc.client_code, 1, 1) IN ('6', '9')
                 WHERE b.filial_code = 1037
                   AND b.modified_on >= (SELECT op_date FROM params)
                   AND b.modified_on <  (SELECT op_date + 1 FROM params)

                 UNION

                 -- CRM kartalar da faollik
                 SELECT DISTINCT c.claim_id
                 FROM fbcrm_cc_claims_hs c
                          JOIN fbcrm_cc_cards_hs h ON h.cc_id = c.cc_id
                          JOIN ln_claim lc ON lc.claim_id = c.claim_id
                     AND lc.filial_code = 1037
                     AND SUBSTR(lc.client_code, 1, 1) IN ('6', '9')
                 WHERE h.filial_code = 1037
                   AND h.state_id != -1
            AND h.stage_id NOT IN (10, 60, 70)
            AND h.modified_on >= (SELECT op_date FROM params)
            AND h.modified_on <  (SELECT op_date + 1 FROM params)

        UNION

        -- CRM register da faollik
        SELECT DISTINCT c.claim_id
        FROM Fbcrm_Vf_Registers_Hs v
            JOIN fbcrm_cc_claims_hs c ON c.cc_id = v.cc_id
            JOIN Fbcrm_Vf_Reg_Protocols p
            ON p.Register_Id = v.Register_Id AND p.State_Id = v.State_Id
            JOIN ln_claim lc ON lc.claim_id = c.claim_id
            AND lc.filial_code = 1037
            AND SUBSTR(lc.client_code, 1, 1) IN ('6', '9')
        WHERE v.filial_code = 1037
          AND p.state_id <> 10
          AND p.modified_on >= (SELECT op_date FROM params)
          AND p.modified_on <  (SELECT op_date + 1 FROM params)

        UNION

        -- Tranzaksiyalarda faollik
        SELECT DISTINCT cl.claim_id
        FROM transacts_history t
            JOIN leads_history l ON l.id = t.lead_id AND l.code_filial = t.code_filial
            JOIN lead_protocol_hist p ON p.lead_id = l.id AND p.code_filial = l.code_filial
            JOIN ln_account n ON n.acc_id = t.acc_id
            AND n.filial_code = 1037
            AND n.loan_type_account = 1
            JOIN ln_claim cl ON cl.filial_code = 1037
            AND SUBSTR(cl.client_code, 1, 1) IN ('6', '9')
            AND BRB_REPORTS_PROCESS.Brb_Loan_Id(cl.client_code, cl.claim_id) = n.loan_id
        WHERE t.code_filial = 1037
          AND t.op_dc = 1
          AND p.code_emp != -7
          AND p.new_state_id IS NOT NULL
          AND p.time >= (SELECT op_date FROM params)
          AND p.time <  (SELECT op_date + 1 FROM params)
    ),

    claim_meta AS (
SELECT c.claim_id,
       c.product_id,
       c.client_code,
       c.claim_num,
       c.client_id,
       c.client_uid,
       c.summ_claim / 100 AS loan_summa,
       c.purpose_loan,
       BRB_REPORTS_PROCESS.Brb_Loan_Id(c.client_code, c.claim_id) AS client_loan_id,
       NVL(BRB_REPORTS_PROCESS.Brb_Credit_Procent(c.client_code, c.claim_num, c.product_id), 0) AS loan_procent,
       (c.summ_claim / 100) *
       NVL(BRB_REPORTS_PROCESS.Brb_Credit_Procent(c.client_code, c.claim_num, c.product_id), 0) / 100 / 365 AS loan_procent_sum,
       DECODE(c.currency, '000', 'Сум', Currency.Get_Name(c.currency)) AS code_val,
       BRB_REPORTS_PROCESS.Remove_Symbol(BRB_REPORTS_PROCESS.Brb_Cl_Name(c.claim_id)) AS client_name,
       BRB_REPORTS_PROCESS.Brb_Cl_Code(c.claim_id) AS client_code_text
FROM ln_claim c
         JOIN Ln_Security_Level l ON l.Client_Id = c.Client_Id
WHERE c.filial_code = 1037
  AND c.claim_id IN (SELECT claim_id FROM claims_in_range)
  AND c.parent_claim_id IS NULL
  AND c.claim_date >= TO_DATE('01.01.2026', 'DD.MM.YYYY')
  AND NVL(c.Product_Id, -1) = NVL((SELECT Ln_Init.Get_Module_Product_Id FROM Dual),
                                  NVL(c.Product_Id, -1))
  AND EXISTS (SELECT 1 FROM Ln_Blanks b WHERE b.Claim_Id = c.Claim_Id
                                          AND b.Grace_Period IS NOT NULL)
    ),

                     claim_branch AS (
                         SELECT claim_id, MAX(branch_id) AS branch_id
                         FROM ln_blanks_his
                         WHERE claim_id IN (SELECT claim_id FROM claims_in_range)
                         GROUP BY claim_id
                     ),

                     claim_timing AS (
                         SELECT claim_id,
                                MIN(created_on) AS base_op_begin,
                                MAX(modified_on) AS base_last_modified,
                                MAX(loan_line_purpose) KEEP(DENSE_RANK LAST ORDER BY modified_on) AS latest_loan_purpose
                         FROM ln_blanks_his
                         WHERE claim_id IN (SELECT claim_id FROM claims_in_range)
                         GROUP BY claim_id
                     ),

                     claim_full AS (
                         SELECT cm.claim_id,
                                cm.product_id,
                                cm.client_code,
                                cm.claim_num,
                                cm.client_id,
                                cm.client_uid,
                                cm.loan_summa,
                                cm.loan_procent,
                                cm.loan_procent_sum,
                                cm.purpose_loan AS loan_code,
                                NVL(ct.latest_loan_purpose, cm.purpose_loan) AS loan_name,
                                cm.code_val,
                                cm.client_loan_id,
                                cm.client_name,
                                cm.client_code_text,
                                cb.branch_id AS filial_id,
                                (SELECT q.name_uz
                                 FROM qqb_bank_name_uz q
                                 WHERE q.branch_id = cb.branch_id
                                   AND ROWNUM = 1) AS filial_name,
                                ct.base_op_begin,
                                ct.base_last_modified
                         FROM claim_meta cm
                                  JOIN claim_branch cb ON cb.claim_id = cm.claim_id
                                  JOIN claim_timing ct ON ct.claim_id = cm.claim_id
                     ),

                     sud_accounts AS (
                         SELECT cf.claim_id,
                                (SELECT SUBSTR(n.account_code, -20)
                                 FROM ln_account n
                                 WHERE n.filial_code = 1037
                                   AND n.loan_id = cf.client_loan_id
                                   AND n.loan_type_account = 1
                                   AND ROWNUM = 1) AS client_sud_acc,
                                (SELECT n.acc_id
                                 FROM ln_account n
                                 WHERE n.filial_code = 1037
                                   AND n.loan_id = cf.client_loan_id
                                   AND n.loan_type_account = 1
                                   AND ROWNUM = 1) AS sud_acc_id
                         FROM claim_full cf
                     ),

                     base_hist AS (
                         SELECT b.claim_id,
                                b.action_id,
                                b.prev_level_id,
                                b.level_id,
                                b.stage_id,
                                b.state_id,
                                b.prev_user_id,
                                b.modified_by,
                                b.created_on,
                                b.modified_on,
                                b.loan_line_purpose,
                                b.branch_id,
                                b.filial_code,
                                cf.product_id,
                                cf.loan_summa,
                                cf.loan_procent,
                                cf.loan_procent_sum,
                                cf.loan_code,
                                cf.code_val,
                                cf.client_name,
                                cf.claim_num,
                                cf.client_code_text,
                                cf.client_id,
                                cf.client_uid,
                                sa.client_sud_acc,
                                sa.sud_acc_id,
                                cf.client_loan_id,
                                cf.base_op_begin,
                                (SELECT l.name_text
                                 FROM brb_ln_s_blank_levels_v l
                                 WHERE l.level_id = b.prev_level_id) AS prev_level_name,
                                CASE
                                    WHEN b.action_id = 0
                                        AND ROW_NUMBER() OVER(PARTITION BY b.claim_id ORDER BY b.modified_on) != 1
                                        THEN (SELECT mlm.cur_nls(a.name) FROM ln_s_blank_actions a WHERE a.action_id = 1)
                                    ELSE (SELECT mlm.cur_nls(a.name) FROM ln_s_blank_actions a WHERE a.action_id = b.action_id)
                                    END AS action_name
                         FROM ln_blanks_his b
                                  JOIN claim_full cf ON cf.claim_id = b.claim_id
                                  LEFT JOIN sud_accounts sa ON sa.claim_id = b.claim_id
                         WHERE b.filial_code = 1037
                           AND b.claim_id IN (SELECT claim_id FROM claims_in_range)
                           AND NOT (b.action_id = 1 AND b.prev_level_id IS NULL AND b.modified_by = -7)        /* +YANGI: tizim "Изменить" larni chiqarish */
                     ),

                     hist_with_neighbors AS (
                         SELECT bh.*,
                                LAG(bh.prev_level_name)  OVER(PARTITION BY bh.claim_id ORDER BY bh.modified_on) AS prev_level_name_prev_row,
                                LEAD(bh.prev_level_name) OVER(PARTITION BY bh.claim_id ORDER BY bh.modified_on) AS prev_level_name_next_row
                         FROM base_hist bh
                     ),

                     base_events AS (
                         SELECT x.claim_id,
                                x.prev_level_name AS position,
                                x.product_id,
                                CASE
                                    WHEN NVL(x.prev_level_id, -1) = -1 THEN
                                        x.prev_level_name || ' ' || x.action_name
                                    WHEN x.action_id = 4 THEN
                                        x.prev_level_name || ' ' || x.action_name || ' ' || x.prev_level_name_prev_row
                                    WHEN x.action_id = 3 THEN
                                        x.prev_level_name || ' ' || x.action_name || ' ' || x.prev_level_name_next_row
                                    ELSE
                                        x.prev_level_name || ' ' || x.action_name
                                    END AS process_stage,
                                CASE
                                    WHEN x.prev_level_id = 5 AND x.level_id = 7 AND x.state_id = 4 AND x.action_id = 3
                                        THEN 'Отправлен'
                                    ELSE BRB_REPORTS_PROCESS.Brb_State_Name(x.state_id)
                                    END AS status_step,
                                NVL(x.prev_user_id, x.modified_by) AS user_id,
                                CASE
                                    WHEN x.prev_user_id IS NULL
                                        THEN BRB_REPORTS_PROCESS.Remove_Symbol(BRB_REPORTS_PROCESS.Brb_User_Name(x.modified_by))
                                    ELSE BRB_REPORTS_PROCESS.Remove_Symbol(BRB_REPORTS_PROCESS.Brb_User_Name(x.prev_user_id))
                                    END AS user_name,
                                BRB_REPORTS_PROCESS.Remove_Symbol(BRB_REPORTS_PROCESS.Brb_User_Name(x.prev_user_id)) AS prev_user_name,
                                NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(x.modified_on), x.modified_by),
                                    BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(x.modified_on), x.modified_by)) AS salary_user,
                                NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(x.modified_on), x.modified_by),
                                    BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(x.modified_on), x.modified_by)) * 1.12 AS salary_user_tax,
                                CASE
                                    WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(x.modified_on), x.modified_by) = 0
                                        THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(x.modified_on), x.modified_by)
                                    ELSE (NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(x.modified_on), x.modified_by), 0) * 1.12) /
                                         BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(x.modified_on), x.modified_by)
                                    END AS salary_user_month,
                                CASE
                                    WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(x.modified_on), x.modified_by) = 0
                                        THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(x.modified_on), x.modified_by) / (8 * 60 * 21)
                                    ELSE ((NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(x.modified_on), x.modified_by), 0) * 1.12) /
                                          BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(x.modified_on), x.modified_by)) / (8 * 60 * 21)
                                    END AS salary_user_min,
                                NVL(BRB_REPORTS_PROCESS.Brb_Level_Name(x.prev_level_id),
                                    BRB_REPORTS_PROCESS.Brb_Level_Name(x.level_id)) AS user_job,
                                x.created_on  AS user_op_begin,
                                x.modified_on AS user_op_end,
                                x.loan_summa,
                                x.loan_procent,
                                x.loan_procent_sum,
                                x.loan_code,
                                x.loan_line_purpose AS loan_name,
                                x.code_val,
                                x.branch_id AS filial_id,
                                (SELECT q.name_uz FROM qqb_bank_name_uz q WHERE q.branch_id = x.branch_id AND ROWNUM = 1) AS filial_name,
                                x.client_name,
                                x.modified_on AS modified_on,
                                DECODE(x.stage_id, 1, '1 этап', '2 этап', 'N/A') AS stage_name,
                                x.claim_num,
                                x.client_code_text AS client_code,
                                x.client_id,
                                x.client_uid,
                                x.client_sud_acc,
                                x.sud_acc_id,
                                x.client_loan_id,
                                x.modified_on AS event_time
                         FROM hist_with_neighbors x
                         WHERE x.modified_on >= (SELECT op_date FROM params)
                           AND x.modified_on <  (SELECT op_date + 1 FROM params)
                     ),

                     trans_events AS (
                         SELECT cf.claim_id,
                                CAST(NULL AS VARCHAR2(200)) AS position,
                                cf.product_id,
                                CASE
                                    WHEN p.new_state_id = 41 AND p.code_emp = -7 THEN '(Администратор IABS провёл)'
                                    WHEN p.new_state_id = 11 THEN 'Перевод сформирован'
                                    WHEN p.new_state_id IN (41, 50, 32) THEN 'Перевод подтверждён'
                                    WHEN p.new_state_id IN (21) THEN 'Перевод возвращён'
                                    ELSE NVL(BRB_REPORTS_PROCESS.Remove_Symbol(p.description), 'Транзакция-' || p.new_state_id)
                                    END AS process_stage,
                                CASE
                                    WHEN p.new_state_id = 41 AND p.code_emp = -7 THEN 'Проведен'
                                    WHEN p.new_state_id = 11 THEN 'Введен'
                                    WHEN p.new_state_id IN (41, 50) THEN 'Бош Хисobchi Утв.ГлБ и Отправил в КТЦ'
                                    ELSE BRB_REPORTS_PROCESS.Brb_State_Name(p.new_state_id)
                                    END AS status_step,
                                p.code_emp AS user_id,
                                BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(p.code_emp)) AS user_name,
                                BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(p.code_emp)) AS prev_user_name,
                                NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.time), p.code_emp),
                                    BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(p.time), p.code_emp)) AS salary_user,
                                NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.time), p.code_emp),
                                    BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(p.time), p.code_emp)) * 1.12 AS salary_user_tax,
                                CASE
                                    WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.time), p.code_emp) = 0
                                        THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(p.time), p.code_emp)
                                    ELSE (NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.time), p.code_emp), 0) * 1.12) /
                                         BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.time), p.code_emp)
                                    END AS salary_user_month,
                                CASE
                                    WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.time), p.code_emp) = 0
                                        THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(p.time), p.code_emp) / (8 * 60 * 21)
                                    ELSE ((NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.time), p.code_emp), 0) * 1.12) /
                                          BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.time), p.code_emp)) / (8 * 60 * 21)
                                    END AS salary_user_min,
                                BRB_REPORTS_PROCESS.Brb_Post_Name(p.code_emp) AS user_job,
                                cf.base_op_begin AS user_op_begin,
                                p.time AS user_op_end,
                                cf.loan_summa,
                                cf.loan_procent,
                                cf.loan_procent_sum,
                                cf.loan_code,
                                cf.loan_name,
                                cf.code_val,
                                cf.filial_id,
                                cf.filial_name,
                                cf.client_name,
                                p.time AS modified_on,
                                'Transact-' || p.new_state_id AS stage_name,
                                cf.claim_num,
                                cf.client_code_text AS client_code,
                                cf.client_id,
                                cf.client_uid,
                                sa.client_sud_acc,
                                sa.sud_acc_id,
                                cf.client_loan_id,
                                p.time AS event_time
                         FROM transacts_history t
                                  JOIN leads_history l
                                       ON l.id = t.lead_id AND l.code_filial = t.code_filial
                                  JOIN lead_protocol_hist p
                                       ON p.lead_id = l.id AND p.code_filial = l.code_filial
                                  JOIN sud_accounts sa ON sa.sud_acc_id = t.acc_id
                                  JOIN claim_full cf ON cf.claim_id = sa.claim_id
                         WHERE t.code_filial = 1037
                           AND p.code_emp != -7
                           AND p.new_state_id IS NOT NULL
                           AND t.op_dc = 1
                           AND p.time >= (SELECT op_date FROM params)
                           AND p.time <  (SELECT op_date + 1 FROM params)
                     ),

                     crm_card_history AS (
                         SELECT h.cc_id,
                                h.stage_id,
                                MAX(h.state_id) AS state_id,
                                MAX(h.modified_by) AS modified_by,
                                MAX(h.modified_on) AS modified_on
                         FROM fbcrm_cc_cards_hs h
                                  JOIN fbcrm_cc_claims_hs c ON c.cc_id = h.cc_id
                         WHERE h.filial_code = 1037
                           AND c.claim_id IN (SELECT claim_id FROM claims_in_range)
                           AND h.state_id != -1
                           AND h.stage_id NOT IN (10, 60, 70)
                           AND h.modified_on >= (SELECT op_date FROM params)
                           AND h.modified_on <  (SELECT op_date + 1 FROM params)
                         GROUP BY h.cc_id, h.stage_id
                     ),

                     crm_card_events AS (
                         SELECT cf.claim_id,
                                (SELECT CASE WHEN h.Dep_Parent_Code IN ('012108') THEN 'Андеррайтер' ELSE '' END
                                 FROM hr_emps_v h
                                 WHERE h.Emp_Id IN (SELECT q.pers_id FROM core_users q WHERE q.user_id = crm.modified_by)) AS position,
                                cf.product_id,
                                DECODE(crm.stage_id,
                                       '20', 'Подбор продукта',
                                       '30', 'Кредитная анкета',
                                       '40', 'Ввод Обеспечения',
                                       '50', 'Расчет Скоринга',
                                       '1',  'Менеджер андеррайтерга жунатди',
                                       'CRM-' || crm.stage_id) AS process_stage,
                                NVL(state.name, 'CRM-' || crm.state_id) AS status_step,
                                crm.modified_by AS user_id,
                                BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(crm.modified_by)) AS user_name,
                                BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(crm.modified_by)) AS prev_user_name,
                                NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(crm.modified_on), crm.modified_by),
                                    BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(crm.modified_on), crm.modified_by)) AS salary_user,
                                NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(crm.modified_on), crm.modified_by),
                                    BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(crm.modified_on), crm.modified_by)) * 1.12 AS salary_user_tax,
                                CASE
                                    WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(crm.modified_on), crm.modified_by) = 0
                                        THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(crm.modified_on), crm.modified_by)
                                    ELSE (NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(crm.modified_on), crm.modified_by), 0) * 1.12) /
                                         BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(crm.modified_on), crm.modified_by)
                                    END AS salary_user_month,
                                CASE
                                    WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(crm.modified_on), crm.modified_by) = 0
                                        THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(crm.modified_on), crm.modified_by) / (8 * 60 * 21)
                                    ELSE ((NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(crm.modified_on), crm.modified_by), 0) * 1.12) /
                                          BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(crm.modified_on), crm.modified_by)) / (8 * 60 * 21)
                                    END AS salary_user_min,
                                BRB_REPORTS_PROCESS.Brb_Post_Name(crm.modified_by) AS user_job,
                                cf.base_op_begin AS user_op_begin,
                                crm.modified_on AS user_op_end,
                                cf.loan_summa,
                                cf.loan_procent,
                                cf.loan_procent_sum,
                                cf.loan_code,
                                cf.loan_name,
                                cf.code_val,
                                cf.filial_id,
                                cf.filial_name,
                                cf.client_name,
                                crm.modified_on AS modified_on,
                                'CRM-' || crm.stage_id AS stage_name,
                                cf.claim_num,
                                cf.client_code_text AS client_code,
                                cf.client_id,
                                cf.client_uid,
                                sa.client_sud_acc,
                                sa.sud_acc_id,
                                cf.client_loan_id,
                                crm.modified_on AS event_time
                         FROM crm_card_history crm
                                  JOIN fbcrm_cc_claims_hs c ON c.cc_id = crm.cc_id
                                  JOIN claim_full cf ON cf.claim_id = c.claim_id
                                  JOIN sud_accounts sa ON sa.claim_id = cf.claim_id
                                  LEFT JOIN Fbcrm_Cc_r_States_v state ON state.state_id = crm.state_id
                         WHERE crm.state_id NOT IN (10, 60, 70)
                           AND crm.stage_id NOT IN (60, 70)
                     ),

                     crm_register_events AS (
                         SELECT cf.claim_id,
                                (SELECT CASE WHEN h.Dep_Parent_Code IN ('012108') THEN 'Андеррайтер' ELSE '' END
                                 FROM hr_emps_v h
                                 WHERE h.Emp_Id IN (SELECT q.pers_id FROM core_users q WHERE q.user_id = p.modified_by)) AS position,
                                cf.product_id,
                                CASE p.state_id
                                    WHEN 1 THEN 'Менеджер отправил заявку андеррайтеру'
                                    WHEN 2 THEN 'Андеррайтер вернул заявку в исходное состояние'
                                    WHEN 3 THEN 'Руководитель андеррайтеров перераспределил заявку'
                                    WHEN 4 THEN 'Руководитель андеррайтеров перераспределил заявку'
                                    WHEN 5 THEN 'Андеррайтер принял заявку'
                                    WHEN 6 THEN 'Андеррайтер одобрил заявку'
                                    WHEN 7 THEN 'Андеррайтер отклонил заявку'
                                    WHEN 8 THEN 'Менеджер принял заявку на повторную обработку'
                                    ELSE BRB_REPORTS_PROCESS.Remove_Symbol(p.Action_Text)
                                    END AS process_stage,
                                DECODE(p.state_id,
                                       1, 'Введен',
                                       3, 'Распределил',
                                       5, 'Принял',
                                       6, 'Утвердиль',
                                       7, 'Отклонил',
                                       8, 'Отправиль',
                                       'CRM-Регист' || p.state_id) AS status_step,
                                p.modified_by AS user_id,
                                BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(p.modified_by)) AS user_name,
                                BRB_REPORTS_PROCESS.Remove_Symbol(employee.Get_Emp_Name(p.modified_by)) AS prev_user_name,
                                NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.modified_on), p.modified_by),
                                    BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(p.modified_on), p.modified_by)) AS salary_user,
                                NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.modified_on), p.modified_by),
                                    BRB_REPORTS_PROCESS.Brb_Salary_Sum_Null(TRUNC(p.modified_on), p.modified_by)) * 1.12 AS salary_user_tax,
                                CASE
                                    WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.modified_on), p.modified_by) = 0
                                        THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(p.modified_on), p.modified_by)
                                    ELSE (NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.modified_on), p.modified_by), 0) * 1.12) /
                                         BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.modified_on), p.modified_by)
                                    END AS salary_user_month,
                                CASE
                                    WHEN BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.modified_on), p.modified_by) = 0
                                        THEN BRB_REPORTS_PROCESS.Brb_Salary_Count_Null(TRUNC(p.modified_on), p.modified_by) / (8 * 60 * 21)
                                    ELSE ((NVL(BRB_REPORTS_PROCESS.Brb_Salary_Sum(TRUNC(p.modified_on), p.modified_by), 0) * 1.12) /
                                          BRB_REPORTS_PROCESS.Brb_Salary_Count(TRUNC(p.modified_on), p.modified_by)) / (8 * 60 * 21)
                                    END AS salary_user_min,
                                BRB_REPORTS_PROCESS.Brb_Post_Name(p.modified_by) AS user_job,
                                cf.base_op_begin AS user_op_begin,
                                p.modified_on AS user_op_end,
                                cf.loan_summa,
                                cf.loan_procent,
                                cf.loan_procent_sum,
                                cf.loan_code,
                                cf.loan_name,
                                cf.code_val,
                                cf.filial_id,
                                cf.filial_name,
                                cf.client_name,
                                p.modified_on AS modified_on,
                                'CRM-Reg-' || p.state_id AS stage_name,
                                cf.claim_num,
                                cf.client_code_text AS client_code,
                                cf.client_id,
                                cf.client_uid,
                                sa.client_sud_acc,
                                sa.sud_acc_id,
                                cf.client_loan_id,
                                p.modified_on AS event_time
                         FROM Fbcrm_Vf_Registers_Hs v
                                  JOIN fbcrm_cc_claims_hs c ON c.cc_id = v.cc_id
                                  JOIN Fbcrm_Vf_Reg_Protocols p
                                       ON p.Register_Id = v.Register_Id AND p.State_Id = v.State_Id
                                  JOIN claim_full cf ON cf.claim_id = c.claim_id
                                  JOIN sud_accounts sa ON sa.claim_id = cf.claim_id
                         WHERE v.filial_code = 1037
                           AND c.claim_id IN (SELECT claim_id FROM claims_in_range)
                           AND p.state_id <> 10
                           AND p.modified_on >= (SELECT op_date FROM params)
                           AND p.modified_on <  (SELECT op_date + 1 FROM params)
                     ),

                     all_events AS (
                         SELECT * FROM base_events
                         UNION ALL
                         SELECT * FROM trans_events
                         UNION ALL
                         SELECT * FROM crm_card_events
                         UNION ALL
                         SELECT * FROM crm_register_events
                     )

SELECT claim_id,
       NVL(position, 'Менеджер') AS position,
                       product_id,
                       CASE
                           WHEN process_stage = 'Заявка поступила в "Общий реестр"'
                               THEN 'Менеджер направил заявку андеррайтеру'
                           ELSE process_stage
END AS process_stage,
                       event_time AS last_event_time,
                       status_step,
                       user_name,
                       user_id,
                       salary_user_min,
                       user_job,
                       filial_id,
                       client_name,
                       loan_summa,
                       loan_procent,
                       loan_procent_sum,
                       loan_code,
                       loan_name,
                       COUNT(*) AS events_count
                FROM all_events
                GROUP BY claim_id,
                         NVL(position, 'Менеджер'),
                         product_id,
                         process_stage,
                         status_step,
                         user_name,
                         user_id,
                         salary_user_min,
                         user_job,
                         filial_id,
                         client_name,
                         loan_summa,
                         loan_procent,
                         loan_procent_sum,
                         loan_code,
                         loan_name,
                         event_time
            ) sq;

        v_rows_inserted := SQL%ROWCOUNT;
COMMIT;

DBMS_OUTPUT.PUT_LINE(
                'BRB_LOG_FIZ_INSERT: ' || v_rows_inserted ||
                ' qator yuklandi. Sana: ' || TO_CHAR(p_op_date, 'DD.MM.YYYY')
        );

EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_err_code := SQLCODE;
            v_err_msg  := SQLERRM;
            RAISE_APPLICATION_ERROR(
                    -20001,
                    'BRB_LOG_FIZ_INSERT xatosi [' ||
                    TO_CHAR(p_op_date, 'DD.MM.YYYY') || ']: ' ||
                    v_err_code || ' - ' || SUBSTR(v_err_msg, 1, 3500)
            );
END;




    PROCEDURE BRB_LOAD_FIZ_LOG_RANGE(p_start_date IN DATE, p_end_date IN DATE)
AS
        v_curr_date DATE := TRUNC(p_start_date);
        v_end_date  DATE := TRUNC(p_end_date);
BEGIN
        WHILE v_curr_date <= v_end_date LOOP
BEGIN
                    BRB_CREDIT_PROCESS_PKG.BRB_LOG_FIZ_INSERT(p_op_date => v_curr_date);
                    DBMS_OUTPUT.PUT_LINE('SUCCESS => ' || TO_CHAR(v_curr_date, 'DD.MM.YYYY'));
EXCEPTION
                    WHEN OTHERS THEN
                        DBMS_OUTPUT.PUT_LINE(
                                'ERROR => ' || TO_CHAR(v_curr_date, 'DD.MM.YYYY') ||
                                ' | ' || SQLCODE || ' | ' || SUBSTR(SQLERRM, 1, 1000)
                        );
                        RAISE;
END;
                v_curr_date := v_curr_date + 1;
END LOOP;
END BRB_LOAD_FIZ_LOG_RANGE;


    PROCEDURE BRB_LOAD_FIZ_DAILY
AS
BEGIN
        BRB_CREDIT_PROCESS_PKG.BRB_LOG_FIZ_INSERT(p_op_date => TRUNC(SYSDATE) - 1);
END BRB_LOAD_FIZ_DAILY;


    PROCEDURE BRB_LOAD_FIZ_HISTORICAL
AS
BEGIN
        BRB_CREDIT_PROCESS_PKG.BRB_LOAD_FIZ_LOG_RANGE(
                p_start_date => TO_DATE('01.01.2026', 'DD.MM.YYYY'),
                p_end_date   => TRUNC(SYSDATE) - 1
        );
END BRB_LOAD_FIZ_HISTORICAL;

END BRB_CREDIT_PROCESS_PKG;

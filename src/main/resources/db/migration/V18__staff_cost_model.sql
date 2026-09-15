-- Xodim vaqtining tannarxi / the cost of staff time.
--
-- Ilhom manbai: bankning amaldagi hisoboti xodim daqiqasining narxini shunday hisoblagan:
--     oylik_maosh * 1.12 / hodisalar_soni / (8 * 60 * 21)
-- Ikkita muammo bor edi. Birinchisi — "8 soat x 21 kun" va soliq koeffitsiyenti 1.12 ifodaning
-- ichida yozilgan: ular faraz ekani hisobotni o'qiganga ko'rinmaydi va o'zgartirish uchun
-- paketni qayta kompilyatsiya qilish kerak. Ikkinchisi — maosh topilmasa hisobot
-- NVL(ROUND(salary_user_min), 1000) bilan 1000 ni qo'yadi: o'lchangan qiymat bilan to'qilgan
-- qiymat bir ustunda aralashib ketadi va qaysi biri ekanini hech kim ajrata olmaydi.
--
-- Shu sababli farazlar shu yerda — ma'lumot sifatida. Roli bu jadvalda bo'lmagan xodimning
-- tannarxi NULL bo'ladi va hisobotda "—" ko'rinadi; taxminiy raqam bilan to'ldirilmaydi.
--
-- Inspired by the bank's existing report, which computed the cost of a staff minute inside the
-- expression itself. Two problems: the "8 h x 21 days" month and the 1.12 tax factor were buried
-- in arithmetic, invisible as assumptions and unchangeable without recompiling; and an unknown
-- salary silently became the literal 1000, mixing measured and invented values in one column.
-- Here the assumptions are data. A role absent from this table yields NULL, shown as "—".
CREATE TABLE CREDIT_ROLE_COST (
  STAFF_ROLE       VARCHAR2(40) PRIMARY KEY,
  MONTHLY_COST     NUMBER(14,2) NOT NULL,
  HOURS_PER_MONTH  NUMBER(6,2)  NOT NULL,
  OVERHEAD_FACTOR  NUMBER(5,3)  DEFAULT 1.12 NOT NULL,
  CURRENCY         VARCHAR2(3)  DEFAULT 'UZS' NOT NULL
);

COMMENT ON TABLE  CREDIT_ROLE_COST IS
  'Rol boyicha xodim vaqtining tannarxi. Barcha qiymatlar faraz, olchov emas.';
COMMENT ON COLUMN CREDIT_ROLE_COST.HOURS_PER_MONTH IS
  'Ish soatlari: 8 soat x 21 kun = 168. Bank kalendari boshqacha bolsa shu yerda ozgaradi.';
COMMENT ON COLUMN CREDIT_ROLE_COST.OVERHEAD_FACTOR IS
  'Maosh ustidan qoshimcha xarajat (soliq va boshqalar).';

INSERT INTO CREDIT_ROLE_COST (STAFF_ROLE, MONTHLY_COST, HOURS_PER_MONTH) VALUES ('KREDIT_MUTAXASSISI',  6000000, 168);
INSERT INTO CREDIT_ROLE_COST (STAFF_ROLE, MONTHLY_COST, HOURS_PER_MONTH) VALUES ('ANDERRAYTER',         9000000, 168);
INSERT INTO CREDIT_ROLE_COST (STAFF_ROLE, MONTHLY_COST, HOURS_PER_MONTH) VALUES ('QOMITA_AZOSI',       15000000, 168);
INSERT INTO CREDIT_ROLE_COST (STAFF_ROLE, MONTHLY_COST, HOURS_PER_MONTH) VALUES ('OPERATSION_XODIM',    5000000, 168);
COMMIT;

-- Xodim boyicha soro'vlar ACTOR_ID ustida guruhlanadi.
CREATE INDEX IX_CSE_ACTOR ON CREDIT_STAGE_EVENT (ACTOR_ID, ACTOR_ROLE);

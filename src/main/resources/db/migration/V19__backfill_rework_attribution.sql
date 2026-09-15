-- QAYTARILDI bosqichidagi xodim va pickup vaqtini to'ldirish.
--
-- V16 bu bosqichni ACTOR_ID va PICKED_UP_AT'siz yozgan edi. Oqibati ikkita boldi:
--   1. Qaytarilgan arizani qayta tayyorlagan kredit mutaxassisining ishi hech kimga
--      biriktirilmagan - xodimlar hisobotida umuman korinmagan, holbuki qayta ishlash
--      arizalarning 27 %ini qamraydi.
--   2. Tasniflagich pickup'i yoq HUMAN bosqichini boshdan-oxir "ish" deb hisoblaydi, shu
--      sababli 13 378 soat navbat xodim ishi sifatida hisoblangan (haqiqiy ish 21 728 soat).
--
-- V16 tuzatildi; bu migratsiya mavjud qatorlarni ham o'sha mantiq bo'yicha to'ldiradi.
-- ENTERED_AT va COMPLETED_AT tegilmaydi, ya'ni arizaning umumiy davomiyligi o'zgarmaydi -
-- faqat bosqich ichidagi navbat/ish ajratimi va kimga tegishliligi aniqlanadi.
--
-- Backfills the actor and pickup time V16 omitted on the rework stage. Entry and completion are
-- left untouched, so no application's elapsed duration changes; only the queue/work split inside
-- the stage and its attribution.
DECLARE
  l_work   NUMBER;
  l_span   NUMBER;
  l_staff  VARCHAR2(20);
  l_fixed  PLS_INTEGER := 0;
BEGIN
  -- Takrorlanuvchi bo'lishi uchun urug' qat'iy belgilanadi.
  DBMS_RANDOM.SEED(20260911);

  FOR r IN (SELECT e.EVENT_ID, e.APP_ID, e.BRANCH_CODE,
                   (CAST(e.COMPLETED_AT AS DATE) - CAST(e.ENTERED_AT AS DATE)) * 24 AS SPAN_H
              FROM CREDIT_STAGE_EVENT e
             WHERE e.TO_STAGE = 'QAYTARILDI'
               AND e.PICKED_UP_AT IS NULL
             ORDER BY e.EVENT_ID)
  LOOP
    -- Log-normal, generatordagi kabi: median 0.75 soat.
    l_work := EXP(LN(0.75) + 0.7 * DBMS_RANDOM.NORMAL);
    l_span := NVL(r.SPAN_H, 0);
    -- Ish vaqti bosqich oralig'idan uzun bo'lib qolmasligi kerak.
    IF l_span > 0 AND l_work > l_span * 0.9 THEN
      l_work := l_span * 0.9;
    END IF;

    SELECT STAFF_ID INTO l_staff FROM (
      SELECT STAFF_ID FROM CREDIT_STAFF
       WHERE STAFF_ROLE = 'KREDIT_MUTAXASSISI'
         AND (BRANCH_CODE = r.BRANCH_CODE OR r.BRANCH_CODE IS NULL)
       ORDER BY ORA_HASH(STAFF_ID || r.APP_ID)
    ) WHERE ROWNUM = 1;

    UPDATE CREDIT_STAGE_EVENT
       SET PICKED_UP_AT = COMPLETED_AT - NUMTODSINTERVAL(l_work * 3600, 'SECOND'),
           ACTOR_ID     = l_staff,
           ACTOR_ROLE   = 'KREDIT_MUTAXASSISI'
     WHERE EVENT_ID = r.EVENT_ID;
    l_fixed := l_fixed + 1;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('QAYTARILDI to''ldirildi: ' || l_fixed || ' qator');
END;
/

-- Hech qaysi HUMAN bosqichi pickup'siz qolmasligi kerak. Jim o'tib ketmasligi uchun tekshiriladi.
DECLARE
  l_gap PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_gap
    FROM CREDIT_STAGE_EVENT e JOIN CREDIT_STAGE s ON s.STAGE_CODE = e.TO_STAGE
   WHERE s.STAGE_TYPE = 'HUMAN' AND e.PICKED_UP_AT IS NULL;
  IF l_gap > 3 THEN
    RAISE_APPLICATION_ERROR(-20019,
      'Pickup vaqti yo''q HUMAN bosqichlari qoldi: ' || l_gap);
  END IF;
  DBMS_OUTPUT.PUT_LINE('Tekshiruv OK. Pickup yo''q HUMAN hodisalar: ' || l_gap);
END;
/

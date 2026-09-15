-- Two corrections.
--
-- 1. The stage name "Skoring, KBI, MIB, Soliq tekshiruvi" contains commas, and the analysis
--    spools CSV. The name broke the column alignment of every downstream row. Separators inside
--    a field are a data-format bug, not a display one, so the name is changed rather than the
--    reader being taught to cope.
UPDATE CREDIT_STAGE
   SET STAGE_NAME = 'Skoring / KBI / MIB / Soliq tekshiruvi'
 WHERE STAGE_CODE = 'TASHQI_TEKSHIRUV';
COMMIT;

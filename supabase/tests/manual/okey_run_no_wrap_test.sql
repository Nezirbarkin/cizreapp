-- =============================================================================
-- 101 Okey Plus — SERİ 13TE BİTER (13ten sonra 1 GELMEZ)
--   supabase db query --linked --file supabase/tests/manual/okey_run_no_wrap_test.sql
--
-- KURAL DEĞİŞİKLİĞİ: Önceki kural kitapçığı 12-13-1i geçerli sayıyordu.
-- Kullanıcı "11-12-13ten sonra sayı gelmez" diyerek sarmayı kaldırdı.
-- =============================================================================

BEGIN;
DO $$
DECLARE v_okey jsonb := '{"color":"red","number":8,"isFalseJoker":false}';

BEGIN
  -- [1] 11-12-13 gecerli
  IF NOT public.okey_is_valid_run(
    '[{"color":"blue","number":11,"isFalseJoker":false},
      {"color":"blue","number":12,"isFalseJoker":false},
      {"color":"blue","number":13,"isFalseJoker":false}]'::jsonb, v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: 11-12-13 gecersiz sayildi';
  END IF;
  RAISE NOTICE 'TEST_OK[1]: 11-12-13 gecerli';

  -- [2] 12-13-1 GECERSIZ (sarma kaldirildi)
  IF public.okey_is_valid_run(
    '[{"color":"blue","number":12,"isFalseJoker":false},
      {"color":"blue","number":13,"isFalseJoker":false},
      {"color":"blue","number":1,"isFalseJoker":false}]'::jsonb, v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: 12-13-1 hala gecerli — 13ten sonra sayi gelmemeli';
  END IF;
  RAISE NOTICE 'TEST_OK[2]: 12-13-1 gecersiz';

  -- [3] 11-12-13-1 GECERSIZ
  IF public.okey_is_valid_run(
    '[{"color":"blue","number":11,"isFalseJoker":false},
      {"color":"blue","number":12,"isFalseJoker":false},
      {"color":"blue","number":13,"isFalseJoker":false},
      {"color":"blue","number":1,"isFalseJoker":false}]'::jsonb, v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: 11-12-13-1 hala gecerli';
  END IF;
  RAISE NOTICE 'TEST_OK[3]: 11-12-13-1 gecersiz';

  -- [4] 1-2-3 gecerli (seri 1den baslar)
  IF NOT public.okey_is_valid_run(
    '[{"color":"blue","number":1,"isFalseJoker":false},
      {"color":"blue","number":2,"isFalseJoker":false},
      {"color":"blue","number":3,"isFalseJoker":false}]'::jsonb, v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: 1-2-3 gecersiz sayildi';
  END IF;
  RAISE NOTICE 'TEST_OK[4]: 1-2-3 gecerli';

  RAISE NOTICE '=== SERI SARMA TESTLERI GECTI ===';
END $$;
ROLLBACK;

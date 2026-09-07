-- =============================================================================
-- 101 Okey Plus — SAHTE OKEY SERBEST JOKER DEĞİLDİR
--   supabase db query --linked --file supabase/tests/manual/okey_false_joker_test.sql
--
-- BULUNAN HATA: Sunucu, sahte okeyi HER TAŞIN yerine geçebilen serbest bir
-- joker olarak işliyordu. RULES.md §1 ise şunu söylüyordu: "Sahte okey
-- taşları, okey taşının yerine NORMAL SAYI DEĞERİYLE geçer".
--
-- Kullanıcı örneği: sahte okey 11 ise, aynı renk 10-11-12'ye ya da farklı
-- renklerden 11-11-11'e girer — BAŞKA YERE DEĞİL.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_okey  jsonb := '{"color":"red","number":11,"isFalseJoker":false}';
  v_fake  jsonb := '{"color":null,"number":null,"isFalseJoker":true}';
BEGIN
  -- [1] Sahte okey JOKER SAYILMAZ; gerçek okey sayılır
  IF public.okey_tile_is_joker(v_fake, v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: sahte okey hala serbest joker!';
  END IF;
  IF NOT public.okey_tile_is_joker(v_okey, v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: gercek okey joker sayilmiyor';
  END IF;
  RAISE NOTICE 'TEST_OK[1]: yalnizca gercek okey joker';

  -- [2] Sahte okey OKEY taşının kimliğini alır
  IF public.okey_tile_color(v_fake, v_okey) <> 'red'
     OR public.okey_tile_number(v_fake, v_okey) <> 11 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: sahte okey okey kimligini almiyor';
  END IF;
  RAISE NOTICE 'TEST_OK[2]: sahte okey = kirmizi 11';

  -- [3] KULLANICI ÖRNEĞİ: aynı renk 10-11-12
  IF NOT public.okey_is_valid_run(
      jsonb_build_array(
        '{"color":"red","number":10,"isFalseJoker":false}'::jsonb,
        v_fake,
        '{"color":"red","number":12,"isFalseJoker":false}'::jsonb),
      v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: sahte okey kendi seri­sine giremedi';
  END IF;
  RAISE NOTICE 'TEST_OK[3]: sahte okey 10-11-12 serisine giriyor';

  -- [4] KULLANICI ÖRNEĞİ: 11-11-11 farklı renk
  IF NOT public.okey_is_valid_set(
      jsonb_build_array(
        '{"color":"blue","number":11,"isFalseJoker":false}'::jsonb,
        '{"color":"black","number":11,"isFalseJoker":false}'::jsonb,
        v_fake),
      v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: sahte okey kendi grubuna giremedi';
  END IF;
  RAISE NOTICE 'TEST_OK[4]: sahte okey 11-11-11 grubuna giriyor';

  -- [5] BAŞKA RENKTEKİ seriye GİREMEZ
  IF public.okey_is_valid_run(
      jsonb_build_array(
        '{"color":"blue","number":10,"isFalseJoker":false}'::jsonb,
        v_fake,
        '{"color":"blue","number":12,"isFalseJoker":false}'::jsonb),
      v_okey) THEN
    RAISE EXCEPTION
      'TEST_FAIL[5]: sahte okey BASKA RENKTEKI seriye girdi — serbest joker gibi davraniyor';
  END IF;
  RAISE NOTICE 'TEST_OK[5]: baska renkteki seriye giremiyor';

  -- [6] BAŞKA SAYIDAKİ gruba GİREMEZ
  IF public.okey_is_valid_set(
      jsonb_build_array(
        '{"color":"blue","number":5,"isFalseJoker":false}'::jsonb,
        '{"color":"black","number":5,"isFalseJoker":false}'::jsonb,
        v_fake),
      v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[6]: sahte okey 5-5-5 grubuna girdi';
  END IF;
  RAISE NOTICE 'TEST_OK[6]: baska sayidaki gruba giremiyor';

  -- [7] GERÇEK okey serbest jokerdir
  IF NOT public.okey_is_valid_run(
      jsonb_build_array(
        '{"color":"blue","number":3,"isFalseJoker":false}'::jsonb,
        '{"color":"blue","number":4,"isFalseJoker":false}'::jsonb,
        v_okey),
      v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[7]: gercek okey joker gibi davranmiyor';
  END IF;
  RAISE NOTICE 'TEST_OK[7]: gercek okey her yere giriyor';

  -- [8] Sahte okey ÇİFTİ yalnızca okey taşıyla
  IF NOT public.okey_is_valid_pair(jsonb_build_array(v_fake, v_okey), v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[8]: sahte okey + okey cift olmadi';
  END IF;
  IF public.okey_is_valid_pair(
      jsonb_build_array(
        v_fake, '{"color":"blue","number":5,"isFalseJoker":false}'::jsonb),
      v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[8]: sahte okey her tasla cift yapiyor';
  END IF;
  RAISE NOTICE 'TEST_OK[8]: sahte okey yalnizca okey tasiyla cift';

  RAISE NOTICE '=== SAHTE OKEY TESTLERI GECTI ===';
END $$;

ROLLBACK;

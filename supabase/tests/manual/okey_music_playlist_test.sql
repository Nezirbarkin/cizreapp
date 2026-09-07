-- =============================================================================
-- 101 Okey Plus — ÇOKLU ŞARKI (çalma listesi)
--   supabase db query --linked --file supabase/tests/manual/okey_music_playlist_test.sql
--
-- Doğrulanan davranış:
--   [1] Birden çok şarkı eklenebilir ve birbirinin ÜZERİNE YAZMAZ
--   [2] Şarkı silinebilir ve depo yolu döner (dosya da kaldırılabilsin)
--   [3] Eski TEK şarkı (background_music) listede kalır — geriye dönük uyum
-- =============================================================================

BEGIN;
DO $$
DECLARE v_admin uuid; v_k1 text; v_k2 text; v_n int; v_path text;
BEGIN
  SELECT id INTO v_admin FROM public.profiles ORDER BY created_at ASC LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'TEST_SKIP: admin degil'; END IF;

  -- [1] Birden cok sarki eklenebilmeli (uzerine yazmamali)
  SELECT public.admin_okey_add_music('music/1.m4a','https://x.invalid/1.m4a','Sarki A') INTO v_k1;
  SELECT public.admin_okey_add_music('music/2.mp3','https://x.invalid/2.mp3','Sarki B') INTO v_k2;
  IF v_k1 = v_k2 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: ayni anahtar uretildi — sarkilar birbirini eziyor';
  END IF;

  SELECT count(*)::int INTO v_n FROM public.okey_list_music()
  WHERE sound_key IN (v_k1, v_k2);
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: 2 sarki listelenmedi (%)', v_n;
  END IF;
  RAISE NOTICE 'TEST_OK[1]: coklu sarki eklenip listeleniyor';

  -- [2] Silme depo yolunu donmeli (dosya da silinebilsin)
  SELECT public.admin_okey_clear_sound(v_k1) INTO v_path;
  IF v_path IS DISTINCT FROM 'music/1.m4a' THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: silme depo yolunu dondurmedi (%)', v_path;
  END IF;
  SELECT count(*)::int INTO v_n FROM public.okey_list_music() WHERE sound_key = v_k1;
  IF v_n <> 0 THEN RAISE EXCEPTION 'TEST_FAIL[2]: sarki silinmedi'; END IF;
  RAISE NOTICE 'TEST_OK[2]: sarki silinebiliyor, dosya yolu donuyor';

  -- [3] Eski TEK sarki da listede kalmali (geriye donuk uyum)
  PERFORM public.admin_okey_set_sound('background_music','bg/1.mp3','https://x.invalid/bg.mp3');
  SELECT count(*)::int INTO v_n FROM public.okey_list_music()
  WHERE sound_key = 'background_music';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: eski tek sarki listeye girmedi';
  END IF;
  RAISE NOTICE 'TEST_OK[3]: eski tek sarki hala calisiyor';

  RAISE NOTICE '=== CALMA LISTESI TESTLERI GECTI ===';
END $$;
ROLLBACK;

-- =============================================================================
-- 101 Okey Plus — ADMIN BOT PROFİLLERİ
--   supabase db query --linked --file supabase/tests/manual/okey_bot_profiles_test.sql
--
-- Doğrulanan davranış:
--   [1] Admin bot profili oluşturabilir
--   [2] Masaya oturan botlara profil ATANIR
--   [3] Aynı masada aynı profil İKİ KEZ kullanılmaz
--
-- Botların önceden kimliği yoktu; masada hepsi "Bot 1", "Bot 2" görünüyordu.
-- =============================================================================

BEGIN;
DO $$
DECLARE
  v_admin uuid; v_p public.okey_bot_profiles%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE; v_named int; v_i int;
BEGIN
  SELECT id INTO v_admin FROM public.profiles ORDER BY created_at ASC LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'TEST_SKIP: admin degil';
  END IF;

  UPDATE public.okey_settings SET room_creation_fee = 0 WHERE id = true;

  -- 3 bot profili olustur
  FOR v_i IN 1 .. 3 LOOP
    SELECT * INTO v_p FROM public.admin_okey_upsert_bot_profile(
      NULL, 'TestBot' || v_i, 'https://example.invalid/' || v_i || '.png', true);
    IF v_p.id IS NULL THEN
      RAISE EXCEPTION 'TEST_FAIL[1]: bot profili olusturulamadi';
    END IF;
  END LOOP;
  RAISE NOTICE 'TEST_OK[1]: bot profilleri olusturuldu';

  -- Oda kur + botlarla doldur
  SELECT * INTO v_room FROM public.create_okey_room(
    false, 'katlamasiz', 'essiz', 'yardimli', 3);
  PERFORM public.okey_fill_with_bots(v_room.id);

  SELECT count(*)::int INTO v_named FROM public.okey_room_players rp
  WHERE rp.room_id = v_room.id AND rp.is_bot AND rp.bot_profile_id IS NOT NULL;

  IF v_named < 3 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: botlara profil atanmadi (% adet)', v_named;
  END IF;
  RAISE NOTICE 'TEST_OK[2]: % bota profil atandi', v_named;

  -- Ayni profil iki kez kullanilmamali
  IF EXISTS (
    SELECT bot_profile_id FROM public.okey_room_players
    WHERE room_id = v_room.id AND bot_profile_id IS NOT NULL
    GROUP BY bot_profile_id HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: ayni profil birden fazla koltukta';
  END IF;
  RAISE NOTICE 'TEST_OK[3]: her bot farkli profil aldi';

  RAISE NOTICE '=== BOT PROFILI TESTLERI GECTI ===';
END $$;
ROLLBACK;

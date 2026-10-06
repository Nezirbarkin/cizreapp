-- Görev 4.1 — 101 Okey modül anahtarı canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/okey_module_toggle_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_user uuid;
  v_admin uuid;
  v_room uuid;
  v_hint text; v_state text;
  v_checks integer := 0;
BEGIN
  SELECT id INTO v_user FROM public.profiles WHERE role::text = 'customer' AND NOT COALESCE(is_bot, false) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_room FROM public.okey_rooms ORDER BY created_at DESC LIMIT 1;
  IF v_user IS NULL OR v_admin IS NULL OR v_room IS NULL THEN RAISE EXCEPTION 'test verisi yok'; END IF;
  DELETE FROM public.okey_room_spectators WHERE user_id IN (v_user, v_admin);

  -- [1] yapı: dört tetikleyici, varsayılan açık, misafir okuyabilir
  IF (SELECT count(*) FROM pg_trigger WHERE tgname IN (
        'trg_okey_rooms_module_guard', 'trg_okey_room_players_module_guard',
        'trg_okey_room_spectators_module_guard', 'trg_okey_room_invites_module_guard')) <> 4 THEN
    RAISE EXCEPTION '[1] tetikleyiciler eksik';
  END IF;
  IF NOT public.okey_module_enabled() OR NOT has_function_privilege('anon', 'public.okey_module_enabled()', 'EXECUTE') THEN
    RAISE EXCEPTION '[1] varsayılan/yetki';
  END IF;
  v_checks := v_checks + 1;

  -- [2] kapalıyken kullanıcı yeni kayıt açamaz (izleyici + davet)
  UPDATE public.app_settings SET value = '"false"'::jsonb WHERE key = 'okey_module_enabled';
  IF public.okey_module_enabled() THEN RAISE EXCEPTION '[2] "false" metni kapalı okunmadı'; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    INSERT INTO public.okey_room_spectators (room_id, user_id) VALUES (v_room, v_user);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_state = MESSAGE_TEXT;
  END;
  IF v_hint IS DISTINCT FROM 'OKEY_DISABLED' THEN RAISE EXCEPTION '[2] izleyici: % %', v_hint, v_state; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    INSERT INTO public.okey_room_invites (room_id, inviter_id, invitee_id, status) VALUES (v_room, v_user, v_admin, 'pending');
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_state = MESSAGE_TEXT;
  END;
  IF v_hint IS DISTINCT FROM 'OKEY_DISABLED' THEN RAISE EXCEPTION '[2] davet: % %', v_hint, v_state; END IF;
  v_checks := v_checks + 1;

  -- [3] kapalıyken yönetici ve sistem bağlamı engellenmez
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    INSERT INTO public.okey_room_spectators (room_id, user_id) VALUES (v_room, v_admin);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_state = MESSAGE_TEXT;
  END;
  IF v_hint = 'OKEY_DISABLED' THEN RAISE EXCEPTION '[3] yönetici engellendi'; END IF;
  INSERT INTO public.okey_room_spectators (room_id, user_id) VALUES (v_room, v_user);  -- oturumsuz (sistem)
  v_checks := v_checks + 1;

  -- [4] açılınca kullanıcı yine tetikleyiciye takılmaz
  DELETE FROM public.okey_room_spectators WHERE user_id = v_user;
  UPDATE public.app_settings SET value = 'true'::jsonb WHERE key = 'okey_module_enabled';
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    INSERT INTO public.okey_room_spectators (room_id, user_id) VALUES (v_room, v_user);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_state = MESSAGE_TEXT;
  END;
  IF v_hint = 'OKEY_DISABLED' THEN RAISE EXCEPTION '[4] açıkken engellendi'; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;

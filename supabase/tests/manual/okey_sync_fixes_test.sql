-- =============================================================================
-- 101 Okey — SENKRON DÜZELTMELERİ testi (göç 20260927000003_okey_sync_fixes)
-- -----------------------------------------------------------------------------
-- ÇALIŞTIRMA:
--   supabase db query --linked --file supabase/tests/manual/okey_sync_fixes_test.sql
--
-- Canlı veritabanında TEK bir DO bloğu olarak çalışır ve HER ZAMAN
-- 'TESTS_PASSED ...' ya da 'TEST_FAIL[...]' istisnasıyla biter; istisna tüm
-- işlemi geri aldığı için hiçbir iz bırakmaz.
--
-- İDDİALAR:
--   [1] okey_match_snapshot eski anahtarların HEPSİNİ + server_now döndürür;
--       server_now sunucunun şimdiki zamanıdır.
--   [2] koltuksuz çağırana da server_now gelir, eli/barajı gelmez.
--   [3] okey_auto_advance: koltuksuz çağıran 'not_seated' (42501) alır.
--   [4] olmayan maç 'not_found' verir.
--   [5] koltuğu olan çağıran için davranış AYNI: süre dolmadan false ve
--       hiçbir şey değişmez; süre dolunca true ve sıra ilerler; bitmiş maçta
--       false.
--   [6] koltuk kontrolü kaynakta FOR UPDATE kilidinden ÖNCE gelir.
--   [7] yetkiler değişmedi: anon çalıştıramaz, authenticated çalıştırır.
-- =============================================================================

DO $$
DECLARE
  v_u1 uuid; v_u2 uuid; v_u3 uuid; v_u4 uuid; v_outsider uuid;
  v_room public.okey_rooms%ROWTYPE;
  v_match public.okey_matches%ROWTYPE;
  v_join record;
  v_snap jsonb;
  v_key text;
  v_result boolean;
  v_turn_before smallint;
  v_phase_before text;
  v_seat_user uuid;
  v_hand_before jsonb;
  v_hand_after jsonb;
  v_raised boolean;
  v_state text;
  v_msg text;
  v_src text;
  v_checks int := 0;
BEGIN
  IF (SELECT count(*) FROM public.profiles) < 5 THEN
    RAISE EXCEPTION 'TEST_SKIP: en az 5 profiles satırı gerekiyor';
  END IF;
  SELECT id INTO v_u1 FROM public.profiles ORDER BY created_at ASC OFFSET 0 LIMIT 1;
  SELECT id INTO v_u2 FROM public.profiles ORDER BY created_at ASC OFFSET 1 LIMIT 1;
  SELECT id INTO v_u3 FROM public.profiles ORDER BY created_at ASC OFFSET 2 LIMIT 1;
  SELECT id INTO v_u4 FROM public.profiles ORDER BY created_at ASC OFFSET 3 LIMIT 1;
  SELECT id INTO v_outsider FROM public.profiles ORDER BY created_at ASC OFFSET 4 LIMIT 1;

  ----------------------------------------------------------------------------
  -- Kurulum: oda + 4 oyuncu + el başlasın (okey_timeout_autoplay_test ile aynı)
  ----------------------------------------------------------------------------
  UPDATE public.okey_settings SET room_creation_fee = 0 WHERE id = true;
  PERFORM public.okey_internal_add_points(v_u1, 100000, 'admin_grant', 'sync:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u2, 100000, 'admin_grant', 'sync:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u3, 100000, 'admin_grant', 'sync:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u4, 100000, 'admin_grant', 'sync:' || gen_random_uuid()::text);

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(false, 'katlamasiz', 'essiz', 'yardimli');
  PERFORM set_config('request.jwt.claim.sub', v_u2::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u2, 'role', 'authenticated')::text, true);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);
  PERFORM set_config('request.jwt.claim.sub', v_u3::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u3, 'role', 'authenticated')::text, true);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);
  PERFORM set_config('request.jwt.claim.sub', v_u4::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u4, 'role', 'authenticated')::text, true);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);

  FOREACH v_seat_user IN ARRAY ARRAY[v_u1, v_u2, v_u3, v_u4] LOOP
    PERFORM set_config('request.jwt.claim.sub', v_seat_user::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_seat_user, 'role', 'authenticated')::text, true);
    PERFORM public.set_okey_ready(v_room.id, true);
  END LOOP;

  SELECT * INTO v_room FROM public.okey_rooms WHERE id = v_room.id;
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_room.current_match_id;
  IF v_match.id IS NULL OR v_match.status <> 'in_progress' THEN
    RAISE EXCEPTION 'TEST_FAIL[0]: el başlamadı';
  END IF;

  ----------------------------------------------------------------------------
  -- [1] Koltuklu oyuncunun masa okuması: eski anahtarlar + server_now
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
  v_snap := public.okey_match_snapshot(v_match.id);
  FOREACH v_key IN ARRAY ARRAY['match', 'hand', 'melds', 'counts', 'moves',
                               'barajs', 'required_opening',
                               'can_undo_side_draw', 'server_now'] LOOP
    IF NOT (v_snap ? v_key) THEN
      RAISE EXCEPTION 'TEST_FAIL[1]: snapshot anahtarı eksik: %', v_key;
    END IF;
    v_checks := v_checks + 1;
  END LOOP;
  IF abs(extract(epoch FROM ((v_snap ->> 'server_now')::timestamptz - now()))) > 1 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: server_now sunucu saati değil: %', v_snap ->> 'server_now';
  END IF;
  IF jsonb_typeof(v_snap -> 'hand') <> 'object' OR jsonb_typeof(v_snap -> 'required_opening') <> 'object' THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: koltuklu oyuncuya el/baraj gelmedi';
  END IF;
  IF (v_snap -> 'match' ->> 'id')::uuid <> v_match.id THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: yanlış maç';
  END IF;
  v_checks := v_checks + 3;

  -- afterMoveId'li okuma da server_now taşır
  v_snap := public.okey_match_snapshot(v_match.id, 0);
  IF NOT (v_snap ? 'server_now') OR jsonb_typeof(v_snap -> 'moves') <> 'array' THEN
    RAISE EXCEPTION 'TEST_FAIL[1b]: hamle sonrası okumada server_now/moves eksik';
  END IF;
  v_checks := v_checks + 1;

  ----------------------------------------------------------------------------
  -- [2] Koltuksuz (izleyici) okuma: server_now var, el/baraj yok
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_outsider, 'role', 'authenticated')::text, true);
  v_snap := public.okey_match_snapshot(v_match.id);
  IF NOT (v_snap ? 'server_now') THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: izleyiciye server_now gelmedi';
  END IF;
  IF jsonb_typeof(v_snap -> 'hand') <> 'null' OR jsonb_typeof(v_snap -> 'required_opening') <> 'null' THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: izleyiciye el/baraj sızdı';
  END IF;
  v_checks := v_checks + 2;

  ----------------------------------------------------------------------------
  -- [3] Koltuksuz çağıran otomatik oynatamaz: not_seated / 42501
  --     (süre DOLMUŞKEN bile — eskiden kilit alıp sonra reddediyordu)
  ----------------------------------------------------------------------------
  UPDATE public.okey_matches SET turn_deadline = now() - interval '5 seconds'
  WHERE id = v_match.id;
  SELECT m.turn_seat, m.turn_phase INTO v_turn_before, v_phase_before
  FROM public.okey_matches m WHERE m.id = v_match.id;

  v_raised := false;
  BEGIN
    PERFORM public.okey_auto_advance(v_match.id);
  EXCEPTION WHEN OTHERS THEN
    v_raised := true;
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF NOT v_raised OR v_state <> '42501' OR v_msg <> 'APP:not_seated' THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: koltuksuz çağıran reddedilmedi (% / %)', v_state, v_msg;
  END IF;
  IF (SELECT turn_seat FROM public.okey_matches WHERE id = v_match.id) <> v_turn_before THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: koltuksuz çağrı sırayı ilerletti';
  END IF;
  v_checks := v_checks + 2;

  ----------------------------------------------------------------------------
  -- [4] Olmayan maç: not_found / P0001
  ----------------------------------------------------------------------------
  v_raised := false;
  BEGIN
    PERFORM public.okey_auto_advance(gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN
    v_raised := true;
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF NOT v_raised OR v_state <> 'P0001' OR v_msg <> 'APP:not_found' THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: olmayan maç (% / %)', v_state, v_msg;
  END IF;
  v_checks := v_checks + 1;

  ----------------------------------------------------------------------------
  -- [5] Koltuklu oyuncu: davranış AYNI
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);

  -- [5a] süre dolmadan: false, hiçbir şey değişmez
  UPDATE public.okey_matches SET turn_deadline = now() + interval '60 seconds'
  WHERE id = v_match.id;
  SELECT h.tiles INTO v_hand_before FROM public.okey_player_hands h
  WHERE h.match_id = v_match.id AND h.seat_no = v_turn_before;
  v_result := public.okey_auto_advance(v_match.id);
  SELECT h.tiles INTO v_hand_after FROM public.okey_player_hands h
  WHERE h.match_id = v_match.id AND h.seat_no = v_turn_before;
  IF v_result IS NOT FALSE
     OR (SELECT turn_seat FROM public.okey_matches WHERE id = v_match.id) <> v_turn_before
     OR v_hand_after <> v_hand_before THEN
    RAISE EXCEPTION 'TEST_FAIL[5a]: süre dolmadan oynattı (%)', v_result;
  END IF;
  v_checks := v_checks + 1;

  -- [5b] süre dolunca: true ve sıra ilerler
  UPDATE public.okey_matches SET turn_deadline = now() - interval '1 second'
  WHERE id = v_match.id;
  v_result := public.okey_auto_advance(v_match.id);
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;
  IF v_result IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST_FAIL[5b]: süre dolunca oynatmadı';
  END IF;
  IF v_match.turn_seat = v_turn_before AND v_match.turn_phase = v_phase_before THEN
    RAISE EXCEPTION 'TEST_FAIL[5b]: sıra ilerlemedi';
  END IF;
  IF v_match.turn_deadline <= now() THEN
    RAISE EXCEPTION 'TEST_FAIL[5b]: yeni sıra süresi verilmedi';
  END IF;
  v_checks := v_checks + 3;

  -- [5c] bitmiş maçta: false (koltuklu çağıran için eskisi gibi)
  UPDATE public.okey_matches SET status = 'finished', turn_deadline = now() - interval '1 second'
  WHERE id = v_match.id;
  v_result := public.okey_auto_advance(v_match.id);
  IF v_result IS NOT FALSE THEN
    RAISE EXCEPTION 'TEST_FAIL[5c]: bitmiş maçta % döndü', v_result;
  END IF;
  v_checks := v_checks + 1;

  ----------------------------------------------------------------------------
  -- [6] Kaynakta sıra: koltuk kontrolü FOR UPDATE'ten önce
  ----------------------------------------------------------------------------
  v_src := pg_get_functiondef('public.okey_auto_advance(uuid)'::regprocedure);
  IF position('APP:not_seated' IN v_src) = 0
     OR position('FOR UPDATE' IN v_src) = 0
     OR position('APP:not_seated' IN v_src) > position('FOR UPDATE' IN v_src) THEN
    RAISE EXCEPTION 'TEST_FAIL[6]: koltuk kontrolü kilitten sonra';
  END IF;
  v_checks := v_checks + 1;

  ----------------------------------------------------------------------------
  -- [7] Yetkiler değişmedi
  ----------------------------------------------------------------------------
  IF has_function_privilege('anon', 'public.okey_auto_advance(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.okey_match_snapshot(uuid,bigint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'TEST_FAIL[7]: anon çalıştırabiliyor';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.okey_auto_advance(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.okey_match_snapshot(uuid,bigint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'TEST_FAIL[7]: authenticated çalıştıramıyor';
  END IF;
  v_checks := v_checks + 2;

  RAISE EXCEPTION 'TESTS_PASSED checks=%', v_checks;
END;
$$;

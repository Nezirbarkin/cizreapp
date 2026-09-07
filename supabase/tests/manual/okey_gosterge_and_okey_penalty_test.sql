-- =============================================================================
-- 101 Okey Plus — GÖSTERGE ÇİFTİ + OKEY CEZALARI + BOT İŞLEME
--   supabase db query --linked --file supabase/tests/manual/okey_gosterge_and_okey_penalty_test.sql
--
-- Doğrulanan kurallar:
--   [1] Göstergeyle aynı TEK taş, başlı başına geçerli bir ÇİFT sayılır
--   [2] 4 gerçek çift + gösterge = 5 çift ile AÇILABİLİR
--   [3] İndirilen gösterge çiftine İŞLEME YAPILAMAZ
--   [4] Normal çifte de işleme yapılamaz
--   [5] Okey ATILIRSA ceza yazılır
--   [6] Okey ELDE KALIRSA ceza yazılır
--   [7] Botlar açtıktan sonra masadaki perlere İŞLEME yapar
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_u1 uuid; v_u2 uuid; v_u3 uuid; v_u4 uuid;
  v_n int;
  v_okey jsonb;
  v_gosterge jsonb;
  v_room public.okey_rooms%ROWTYPE;
  v_match public.okey_matches%ROWTYPE;
  v_join record;
  v_meld_id bigint;
  v_blocked boolean;
  v_score int;
  v_pen int;
BEGIN
  SELECT count(*) INTO v_n FROM public.profiles;
  IF v_n < 4 THEN RAISE EXCEPTION 'TEST_SKIP: 4 profil gerekli'; END IF;
  SELECT id INTO v_u1 FROM public.profiles ORDER BY created_at ASC OFFSET 0 LIMIT 1;
  SELECT id INTO v_u2 FROM public.profiles ORDER BY created_at ASC OFFSET 1 LIMIT 1;
  SELECT id INTO v_u3 FROM public.profiles ORDER BY created_at ASC OFFSET 2 LIMIT 1;
  SELECT id INTO v_u4 FROM public.profiles ORDER BY created_at ASC OFFSET 3 LIMIT 1;

  UPDATE public.okey_settings
  SET room_creation_fee = 0,
      okey_discard_penalty = 101,
      okey_in_hand_penalty = 101
  WHERE id = true;

  -- Masa artık SADECE PUANLA açılır (en az 100)
  PERFORM public.okey_internal_add_points(v_u1, 100000, 'admin_grant',
    'gtest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u2, 100000, 'admin_grant',
    'gtest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u3, 100000, 'admin_grant',
    'gtest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u4, 100000, 'admin_grant',
    'gtest:' || gen_random_uuid()::text);

  -- Gösterge: mavi 7  =>  okey: mavi 8
  v_gosterge := '{"color":"blue","number":7,"isFalseJoker":false}';
  v_okey     := '{"color":"blue","number":8,"isFalseJoker":false}';

  ----------------------------------------------------------------------------
  -- [1] Göstergeyle aynı TEK taş, geçerli bir çift sayılır
  ----------------------------------------------------------------------------
  IF NOT public.okey_is_gosterge_pair(
        jsonb_build_array(v_gosterge), v_gosterge) THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: gosterge cifti tanınmadı';
  END IF;

  -- Gösterge OLMAYAN tek taş çift SAYILMAZ
  IF public.okey_is_gosterge_pair(
        '[{"color":"red","number":5,"isFalseJoker":false}]'::jsonb,
        v_gosterge) THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: gosterge olmayan tek tas cift sayildi!';
  END IF;

  -- Üç parametreli doğrulayıcı ikisini de kabul etmeli
  IF NOT public.okey_is_valid_pair_ex(
        jsonb_build_array(v_gosterge), v_okey, v_gosterge) THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: valid_pair_ex gosterge ciftini reddetti';
  END IF;
  IF NOT public.okey_is_valid_pair_ex(
        '[{"color":"red","number":5,"isFalseJoker":false},
          {"color":"red","number":5,"isFalseJoker":false}]'::jsonb,
        v_okey, v_gosterge) THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: valid_pair_ex normal cifti reddetti';
  END IF;
  RAISE NOTICE 'TEST_OK[1]: gosterge cifti dogru taniniyor';

  ----------------------------------------------------------------------------
  -- Kurulum: 4 oyuncu, el başlasın
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(
    false, 'katlamasiz', 'essiz', 'yardimli', 5);
  PERFORM set_config('request.jwt.claim.sub', v_u2::text, true);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);
  PERFORM set_config('request.jwt.claim.sub', v_u3::text, true);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);
  PERFORM set_config('request.jwt.claim.sub', v_u4::text, true);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  PERFORM public.set_okey_ready(v_room.id, true);
  PERFORM set_config('request.jwt.claim.sub', v_u2::text, true);
  PERFORM public.set_okey_ready(v_room.id, true);
  PERFORM set_config('request.jwt.claim.sub', v_u3::text, true);
  PERFORM public.set_okey_ready(v_room.id, true);
  PERFORM set_config('request.jwt.claim.sub', v_u4::text, true);
  PERFORM public.set_okey_ready(v_room.id, true);

  SELECT * INTO v_room FROM public.okey_rooms WHERE id = v_room.id;
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_room.current_match_id;

  -- Gösterge/okey'i bilinen değerlere sabitle, sırayı koltuk 0'a ver
  UPDATE public.okey_matches
  SET indicator_tile = v_gosterge,
      okey_tile = v_okey,
      turn_seat = 0,
      turn_phase = 'discard'
  WHERE id = v_match.id;
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;

  ----------------------------------------------------------------------------
  -- [2] 4 gerçek çift + GÖSTERGE = 5 çift ile açılabilir
  ----------------------------------------------------------------------------
  UPDATE public.okey_player_hands
  SET tiles = '[
        {"color":"red","number":2,"isFalseJoker":false},
        {"color":"red","number":2,"isFalseJoker":false},
        {"color":"black","number":4,"isFalseJoker":false},
        {"color":"black","number":4,"isFalseJoker":false},
        {"color":"yellow","number":6,"isFalseJoker":false},
        {"color":"yellow","number":6,"isFalseJoker":false},
        {"color":"red","number":9,"isFalseJoker":false},
        {"color":"red","number":9,"isFalseJoker":false},
        {"color":"blue","number":7,"isFalseJoker":false},
        {"color":"black","number":11,"isFalseJoker":false}
      ]'::jsonb,
      is_opening_done = false,
      opened_with_pairs = false,
      penalty_points = 0
  WHERE match_id = v_match.id AND seat_no = 0;

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  -- 2026-09-03: çiftle İLK açılış artık "çifte gidiyorum" beyanını şart koşar
  -- (RULES.md §7 — beyan geri alınamaz, 404 cezasının karşılığıdır).
  PERFORM public.okey_set_went_for_pairs(v_match.id, true);
  PERFORM public.okey_lay_meld(
    v_match.id,
    '[
      [{"color":"red","number":2,"isFalseJoker":false},
       {"color":"red","number":2,"isFalseJoker":false}],
      [{"color":"black","number":4,"isFalseJoker":false},
       {"color":"black","number":4,"isFalseJoker":false}],
      [{"color":"yellow","number":6,"isFalseJoker":false},
       {"color":"yellow","number":6,"isFalseJoker":false}],
      [{"color":"red","number":9,"isFalseJoker":false},
       {"color":"red","number":9,"isFalseJoker":false}],
      [{"color":"blue","number":7,"isFalseJoker":false}]
    ]'::jsonb,
    true);

  SELECT count(*)::int INTO v_n FROM public.okey_table_melds
  WHERE match_id = v_match.id AND laid_by_seat = 0;
  IF v_n <> 5 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: 5 cift indirilemedi (% grup)', v_n;
  END IF;
  RAISE NOTICE 'TEST_OK[2]: 4 cift + gosterge ile ACILDI';

  ----------------------------------------------------------------------------
  -- [3] Gösterge çifti AYRI türde işaretlenmeli ve İŞLENEMEMELİ
  ----------------------------------------------------------------------------
  SELECT id INTO v_meld_id FROM public.okey_table_melds
  WHERE match_id = v_match.id AND meld_type = 'gosterge' LIMIT 1;

  IF v_meld_id IS NULL THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: gosterge cifti ayri turde isaretlenmedi';
  END IF;

  v_blocked := false;
  BEGIN
    PERFORM public.okey_add_to_meld(v_match.id, v_meld_id, v_gosterge);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'APP:gosterge_pair_not_processable%' THEN
      v_blocked := true;
    ELSE
      RAISE;
    END IF;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: gosterge ciftine ISLEME YAPILDI!';
  END IF;
  RAISE NOTICE 'TEST_OK[3]: gosterge ciftine isleme yapilamiyor';

  ----------------------------------------------------------------------------
  -- [4] Normal çifte de işleme yapılamaz
  ----------------------------------------------------------------------------
  SELECT id INTO v_meld_id FROM public.okey_table_melds
  WHERE match_id = v_match.id AND meld_type = 'pair' LIMIT 1;

  v_blocked := false;
  BEGIN
    PERFORM public.okey_add_to_meld(
      v_match.id, v_meld_id,
      '{"color":"red","number":2,"isFalseJoker":false}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'APP:pair_not_processable%' THEN
      v_blocked := true;
    ELSE
      RAISE;
    END IF;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: normal cifte isleme yapildi!';
  END IF;
  RAISE NOTICE 'TEST_OK[4]: cifte isleme yapilamiyor';

  ----------------------------------------------------------------------------
  -- [5] Okey ATILIRSA ceza
  ----------------------------------------------------------------------------
  UPDATE public.okey_matches
  SET turn_seat = 1, turn_phase = 'discard' WHERE id = v_match.id;
  UPDATE public.okey_player_hands
  SET tiles = jsonb_build_array(v_okey,
        '{"color":"red","number":3,"isFalseJoker":false}'::jsonb),
      penalty_points = 0, is_opening_done = true
  WHERE match_id = v_match.id AND seat_no = 1;

  PERFORM public.okey_internal_discard_for_seat(v_match.id, 1::smallint, v_okey);

  SELECT penalty_points INTO v_pen FROM public.okey_player_hands
  WHERE match_id = v_match.id AND seat_no = 1;
  IF COALESCE(v_pen, 0) <> 101 THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: okey atma cezasi yazilmadi (%)', v_pen;
  END IF;
  RAISE NOTICE 'TEST_OK[5]: okey atinca +101 ceza';

  ----------------------------------------------------------------------------
  -- [6] Okey ELDE KALIRSA ceza (el sonunda)
  ----------------------------------------------------------------------------
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;

  -- Koltuk 2'nin elinde OKEY kalsın, cezası sıfırlansın
  UPDATE public.okey_player_hands
  SET tiles = jsonb_build_array(v_okey,
        '{"color":"red","number":3,"isFalseJoker":false}'::jsonb),
      penalty_points = 0, is_opening_done = true, opened_with_pairs = false
  WHERE match_id = v_match.id AND seat_no = 2;

  -- Koltuk 3'ün elinde okey YOK (karşılaştırma için)
  UPDATE public.okey_player_hands
  SET tiles = '[{"color":"red","number":3,"isFalseJoker":false}]'::jsonb,
      penalty_points = 0, is_opening_done = true, opened_with_pairs = false
  WHERE match_id = v_match.id AND seat_no = 3;

  IF v_match.status = 'in_progress' THEN
    PERFORM public.okey_internal_finalize_hand(v_match.id, NULL, NULL);
    SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;
  END IF;

  v_score := COALESCE((v_match.scores ->> '2')::int, 0);
  v_n := COALESCE((v_match.scores ->> '3')::int, 0);

  -- Koltuk 2: 3 (taş değeri) + 101 (okey elde) ; Koltuk 3: sadece 3
  IF v_score - v_n < 101 THEN
    RAISE EXCEPTION
      'TEST_FAIL[6]: okey elde kalma cezasi yansimadi (okeyli=%, okeysiz=%)',
      v_score, v_n;
  END IF;
  RAISE NOTICE 'TEST_OK[6]: okey elde kalinca +101 ceza (% vs %)', v_score, v_n;

  ----------------------------------------------------------------------------
  -- [7] Botlar açtıktan sonra İŞLEME yapar
  ----------------------------------------------------------------------------
  DECLARE
    v_r2 public.okey_rooms%ROWTYPE;
    v_m2 public.okey_matches%ROWTYPE;
    v_s smallint; v_bot boolean; v_t jsonb; v_turn int; v_adds int;
    v_try int;
  BEGIN
    v_adds := 0;
    FOR v_try IN 1 .. 2 LOOP
      PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
      SELECT * INTO v_r2 FROM public.create_okey_room(
        false, 'katlamasiz', 'essiz', 'yardimli', 5);
      PERFORM public.okey_fill_with_bots(v_r2.id);
      SELECT * INTO v_r2 FROM public.okey_rooms WHERE id = v_r2.id;
      SELECT * INTO v_m2 FROM public.okey_matches
      WHERE id = v_r2.current_match_id;
      CONTINUE WHEN v_m2.id IS NULL;

      FOR v_turn IN 1 .. 120 LOOP
        SELECT * INTO v_m2 FROM public.okey_matches WHERE id = v_m2.id;
        EXIT WHEN v_m2.status <> 'in_progress';
        v_s := v_m2.turn_seat;
        SELECT rp.is_bot INTO v_bot FROM public.okey_room_players rp
        WHERE rp.room_id = v_r2.id AND rp.seat_no = v_s;

        IF COALESCE(v_bot, false) THEN
          PERFORM public.okey_bot_take_turn(v_m2.id);
        ELSE
          IF v_m2.turn_phase = 'draw' THEN
            EXIT WHEN v_m2.deck_remaining <= 0;
            PERFORM public.okey_internal_draw_for_seat(v_m2.id, v_s, 'deck');
          END IF;
          SELECT h.tiles INTO v_t FROM public.okey_player_hands h
          WHERE h.match_id = v_m2.id AND h.seat_no = v_s;
          EXIT WHEN v_t IS NULL OR jsonb_array_length(v_t) = 0;
          PERFORM public.okey_internal_discard_for_seat(v_m2.id, v_s, v_t -> 0);
        END IF;
      END LOOP;

      SELECT count(*)::int INTO v_n FROM public.okey_moves
      WHERE match_id = v_m2.id AND action = 'add_to_meld';
      v_adds := v_adds + COALESCE(v_n, 0);
      EXIT WHEN v_adds > 0;
    END LOOP;

    IF v_adds = 0 THEN
      RAISE EXCEPTION
        'TEST_FAIL[7]: botlar hic ISLEME yapmadi (add_to_meld = 0)';
    END IF;
    RAISE NOTICE 'TEST_OK[7]: botlar % isleme yapti', v_adds;
  END;

  RAISE NOTICE '=== GOSTERGE + OKEY CEZASI + BOT ISLEME TESTLERI GECTI ===';
END $$;

ROLLBACK;

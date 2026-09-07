-- =============================================================================
-- 101 Okey Plus — BOT ZEKÂSI + OKEY ATMA CEZASI + EL SAYISI
--   supabase db query --linked --file supabase/tests/manual/okey_bot_and_penalty_test.sql
--
-- Doğrulanan davranışlar:
--   [1] Bot, elindeki perleri BULUR (find_melds boş dönmez)
--   [2] Bot, baraja ulaşan bir elle GERÇEKTEN AÇAR (masaya per koyar)
--   [3] Bot okeyi ASLA atmaz
--   [4] Okey atan oyuncu CEZA alır
--   [5] Ceza, el sonunda skora yansır
--   [6] Maç, seçilen EL SAYISI dolunca biter
--
-- NEDEN [2] KRİTİK: botlar aylarca hiç açmadı ve bu kimsenin dikkatini
-- çekmedi, çünkü hiçbir test botun MASAYA PER KOYDUĞUNU kontrol etmiyordu.
-- Eski bot fonksiyonunun kendi yorumunda "hiç per/grup açmaya çalışmaz"
-- yazıyordu. Bu test tam olarak o boşluğu kapatır.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_u1 uuid; v_u2 uuid; v_u3 uuid; v_u4 uuid;
  v_room public.okey_rooms%ROWTYPE;
  v_match public.okey_matches%ROWTYPE;
  v_join record;
  v_okey jsonb;
  v_hand jsonb;
  v_groups jsonb;
  v_bot_seat smallint;
  v_meld_count int;
  v_pick jsonb;
  v_penalty int;
  v_score int;
BEGIN
  SELECT count(*) INTO v_meld_count FROM public.profiles;
  IF v_meld_count < 4 THEN
    RAISE EXCEPTION 'TEST_SKIP: en az 4 profiles satırı gerekiyor';
  END IF;
  SELECT id INTO v_u1 FROM public.profiles ORDER BY created_at ASC OFFSET 0 LIMIT 1;
  SELECT id INTO v_u2 FROM public.profiles ORDER BY created_at ASC OFFSET 1 LIMIT 1;
  SELECT id INTO v_u3 FROM public.profiles ORDER BY created_at ASC OFFSET 2 LIMIT 1;
  SELECT id INTO v_u4 FROM public.profiles ORDER BY created_at ASC OFFSET 3 LIMIT 1;

  UPDATE public.okey_settings
  SET room_creation_fee = 0, okey_discard_penalty = 101 WHERE id = true;

  -- Masa artık SADECE PUANLA açılır (en az 100); test kullanıcılarına puan ver
  PERFORM public.okey_internal_add_points(v_u1, 100000, 'admin_grant',
    'bottest:' || gen_random_uuid()::text);

  ----------------------------------------------------------------------------
  -- [1] Per bulucu: bilinen bir elde perleri bulmalı
  ----------------------------------------------------------------------------
  v_okey := '{"color":"yellow","number":1,"isFalseJoker":false}';

  -- kirmizi 10-11-12-13 (46) + 13'lu grup (39) + siyah 2-3-4 (9) = 94
  v_hand := '[
    {"color":"red","number":10,"isFalseJoker":false},
    {"color":"red","number":11,"isFalseJoker":false},
    {"color":"red","number":12,"isFalseJoker":false},
    {"color":"red","number":13,"isFalseJoker":false},
    {"color":"blue","number":13,"isFalseJoker":false},
    {"color":"black","number":13,"isFalseJoker":false},
    {"color":"yellow","number":13,"isFalseJoker":false},
    {"color":"black","number":2,"isFalseJoker":false},
    {"color":"black","number":3,"isFalseJoker":false},
    {"color":"black","number":4,"isFalseJoker":false},
    {"color":"blue","number":7,"isFalseJoker":false}
  ]'::jsonb;

  v_groups := public.okey_internal_find_melds(v_hand, v_okey);
  IF jsonb_array_length(COALESCE(v_groups, '[]'::jsonb)) < 2 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: per bulucu perleri bulamadi (%)', v_groups;
  END IF;
  RAISE NOTICE 'TEST_OK[1]: per bulucu % grup buldu',
    jsonb_array_length(v_groups);

  ----------------------------------------------------------------------------
  -- [3] Bot okeyi ASLA atmaz
  ----------------------------------------------------------------------------
  DECLARE
    v_with_okey jsonb;
  BEGIN
    -- Elde okey (sari 1) + yuksek bir cop tasi var
    v_with_okey := '[
      {"color":"yellow","number":1,"isFalseJoker":false},
      {"color":"blue","number":9,"isFalseJoker":false},
      {"color":"red","number":3,"isFalseJoker":false}
    ]'::jsonb;

    v_pick := public.okey_internal_bot_pick_discard(v_with_okey, v_okey);
    IF public.okey_tile_is_joker(v_pick, v_okey) THEN
      RAISE EXCEPTION 'TEST_FAIL[3]: bot OKEYI atti!';
    END IF;
    -- Cop taslarin en yuksegi atilmali (mavi 9)
    IF (v_pick->>'number')::int <> 9 THEN
      RAISE EXCEPTION 'TEST_FAIL[3]: bot en yuksek cop tasi yerine % atti', v_pick;
    END IF;
    RAISE NOTICE 'TEST_OK[3]: bot okeyi atmiyor, en yuksek cop tasini atiyor';
  END;

  ----------------------------------------------------------------------------
  -- Kurulum: 1 gerçek oyuncu + 3 bot, 2 elli maç
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(
    false, 'katlamasiz', 'essiz', 'yardimli', 2);

  IF v_room.total_hands <> 2 THEN
    RAISE EXCEPTION 'TEST_FAIL[6a]: el sayisi kaydedilmedi (%)', v_room.total_hands;
  END IF;
  RAISE NOTICE 'TEST_OK[6a]: oda 2 el olarak kuruldu';

  PERFORM public.okey_fill_with_bots(v_room.id);
  SELECT * INTO v_room FROM public.okey_rooms WHERE id = v_room.id;
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_room.current_match_id;
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'TEST_FAIL: el baslamadi';
  END IF;

  ----------------------------------------------------------------------------
  -- [2] Bot GERÇEKTEN AÇAR — elini baraja yetecek şekilde kurup oynatalım
  ----------------------------------------------------------------------------
  SELECT rp.seat_no INTO v_bot_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_room.id AND rp.is_bot LIMIT 1;

  -- Sirayi bota ver ve eline 101'i gecen perler koy
  UPDATE public.okey_matches
  SET turn_seat = v_bot_seat, turn_phase = 'discard',
      okey_tile = v_okey
  WHERE id = v_match.id;

  UPDATE public.okey_player_hands
  SET tiles = '[
        {"color":"red","number":10,"isFalseJoker":false},
        {"color":"red","number":11,"isFalseJoker":false},
        {"color":"red","number":12,"isFalseJoker":false},
        {"color":"red","number":13,"isFalseJoker":false},
        {"color":"blue","number":13,"isFalseJoker":false},
        {"color":"black","number":13,"isFalseJoker":false},
        {"color":"yellow","number":13,"isFalseJoker":false},
        {"color":"blue","number":5,"isFalseJoker":false},
        {"color":"blue","number":6,"isFalseJoker":false},
        {"color":"blue","number":7,"isFalseJoker":false},
        {"color":"green","number":2,"isFalseJoker":false}
      ]'::jsonb,
      is_opening_done = false
  WHERE match_id = v_match.id AND seat_no = v_bot_seat;

  -- Yesil renk yok; gecerli bir cop tasiyla degistir
  UPDATE public.okey_player_hands
  SET tiles = tiles - (jsonb_array_length(tiles) - 1)
              || '[{"color":"black","number":8,"isFalseJoker":false}]'::jsonb
  WHERE match_id = v_match.id AND seat_no = v_bot_seat;

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  PERFORM public.okey_bot_take_turn(v_match.id);

  SELECT count(*)::int INTO v_meld_count FROM public.okey_table_melds
  WHERE match_id = v_match.id AND laid_by_seat = v_bot_seat;

  IF v_meld_count = 0 THEN
    RAISE EXCEPTION
      'TEST_FAIL[2]: BOT HALA AÇMIYOR — masaya hic per koymadi';
  END IF;
  RAISE NOTICE 'TEST_OK[2]: bot % per acti', v_meld_count;

  ----------------------------------------------------------------------------
  -- [4] Okey atan oyuncu CEZA alır
  ----------------------------------------------------------------------------
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;

  UPDATE public.okey_matches
  SET turn_seat = 0, turn_phase = 'discard', okey_tile = v_okey
  WHERE id = v_match.id;

  UPDATE public.okey_player_hands
  SET tiles = '[
        {"color":"yellow","number":1,"isFalseJoker":false},
        {"color":"red","number":4,"isFalseJoker":false},
        {"color":"blue","number":9,"isFalseJoker":false}
      ]'::jsonb,
      penalty_points = 0,
      is_opening_done = true
  WHERE match_id = v_match.id AND seat_no = 0;

  -- Okeyi (sari 1) at
  PERFORM public.okey_internal_discard_for_seat(
    v_match.id, 0::smallint, v_okey);

  SELECT penalty_points INTO v_penalty FROM public.okey_player_hands
  WHERE match_id = v_match.id AND seat_no = 0;

  IF COALESCE(v_penalty, 0) <> 101 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: okey atma cezasi yazilmadi (%)', v_penalty;
  END IF;
  RAISE NOTICE 'TEST_OK[4]: okey atana 101 ceza yazildi';

  ----------------------------------------------------------------------------
  -- [5] Ceza el sonunda skora yansır
  ----------------------------------------------------------------------------
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;
  IF v_match.status = 'in_progress' THEN
    PERFORM public.okey_internal_finalize_hand(v_match.id, NULL, NULL);
    SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;
  END IF;

  v_score := COALESCE((v_match.scores ->> '0')::int, 0);
  IF v_score < 101 THEN
    RAISE EXCEPTION
      'TEST_FAIL[5]: ceza skora yansimadi (koltuk 0 skoru = %)', v_score;
  END IF;
  RAISE NOTICE 'TEST_OK[5]: ceza skora yansidi (koltuk 0 = %)', v_score;

  ----------------------------------------------------------------------------
  -- [6] Maç, seçilen EL SAYISI dolunca biter
  ----------------------------------------------------------------------------
  DECLARE
    v_r2 public.okey_rooms%ROWTYPE;
    v_m2 public.okey_matches%ROWTYPE;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    SELECT * INTO v_r2 FROM public.create_okey_room(
      false, 'katlamasiz', 'essiz', 'yardimli', 1); -- TEK el
    PERFORM public.okey_fill_with_bots(v_r2.id);

    SELECT * INTO v_r2 FROM public.okey_rooms WHERE id = v_r2.id;
    SELECT * INTO v_m2 FROM public.okey_matches WHERE id = v_r2.current_match_id;

    -- Tek el bitince oda da bitmeli
    PERFORM public.okey_internal_finalize_hand(v_m2.id, NULL, NULL);

    SELECT * INTO v_r2 FROM public.okey_rooms WHERE id = v_r2.id;
    IF v_r2.status <> 'finished' THEN
      RAISE EXCEPTION
        'TEST_FAIL[6]: 1 el secilmisken mac bitmedi (oda: %)', v_r2.status;
    END IF;
    RAISE NOTICE 'TEST_OK[6]: secilen el sayisi dolunca mac bitiyor';
  END;

  ----------------------------------------------------------------------------
  -- [7] GERÇEK OYUN SİMÜLASYONU: bot bir maç boyunca GERÇEKTEN AÇAR MI?
  --
  -- NEDEN AYRI BİR TEST: Yukarıdaki [2] testi bota HAZIR bir el veriyor —
  -- yani "açabiliyor mu" sorusunu ölçüyor. Ama sahadaki şikâyet farklıydı:
  -- bot gerçek bir elde 101 barajına HİÇ ulaşamıyor, dolayısıyla oyunda
  -- yokmuş gibi görünüyordu. Ölçüm bunu doğruladı: botların eli 79 puanda
  -- takılıyordu. Bu test o durumu kovalar — hazır el vermeden, gerçek
  -- dağıtımla oynatır ve en az bir botun açmasını bekler.
  ----------------------------------------------------------------------------
  DECLARE
    v_sim_room public.okey_rooms%ROWTYPE;
    v_sim public.okey_matches%ROWTYPE;
    v_s smallint;
    v_bot boolean;
    v_t jsonb;
    v_turn int;
    v_opened_bots int;
    v_attempt int;
    v_total_opened int := 0;
  BEGIN
    -- Dağıtım rastgele olduğu için iki maç denenir; hiçbirinde bot
    -- açamıyorsa bu gerçek bir gerileme demektir.
    FOR v_attempt IN 1 .. 2 LOOP
      PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
      SELECT * INTO v_sim_room FROM public.create_okey_room(
        false, 'katlamasiz', 'essiz', 'yardimli', 5);
      PERFORM public.okey_fill_with_bots(v_sim_room.id);

      SELECT * INTO v_sim_room FROM public.okey_rooms WHERE id = v_sim_room.id;
      SELECT * INTO v_sim FROM public.okey_matches
      WHERE id = v_sim_room.current_match_id;
      CONTINUE WHEN v_sim.id IS NULL;

      FOR v_turn IN 1 .. 120 LOOP
        SELECT * INTO v_sim FROM public.okey_matches WHERE id = v_sim.id;
        EXIT WHEN v_sim.status <> 'in_progress';

        v_s := v_sim.turn_seat;
        SELECT rp.is_bot INTO v_bot FROM public.okey_room_players rp
        WHERE rp.room_id = v_sim_room.id AND rp.seat_no = v_s;

        IF COALESCE(v_bot, false) THEN
          PERFORM public.okey_bot_take_turn(v_sim.id);
        ELSE
          -- İnsan koltuğu basitçe çeker ve ilk taşı atar
          IF v_sim.turn_phase = 'draw' THEN
            EXIT WHEN v_sim.deck_remaining <= 0;
            PERFORM public.okey_internal_draw_for_seat(v_sim.id, v_s, 'deck');
          END IF;
          SELECT h.tiles INTO v_t FROM public.okey_player_hands h
          WHERE h.match_id = v_sim.id AND h.seat_no = v_s;
          EXIT WHEN v_t IS NULL OR jsonb_array_length(v_t) = 0;
          PERFORM public.okey_internal_discard_for_seat(v_sim.id, v_s, v_t -> 0);
        END IF;
      END LOOP;

      SELECT count(*)::int INTO v_opened_bots
      FROM public.okey_player_hands h
      JOIN public.okey_room_players rp
        ON rp.room_id = v_sim_room.id AND rp.seat_no = h.seat_no
      WHERE h.match_id = v_sim.id AND rp.is_bot AND h.is_opening_done;

      v_total_opened := v_total_opened + COALESCE(v_opened_bots, 0);
      EXIT WHEN v_total_opened > 0;
    END LOOP;

    IF v_total_opened = 0 THEN
      RAISE EXCEPTION
        'TEST_FAIL[7]: BOTLAR GERCEK OYUNDA HIC ACMIYOR — '
        'iki mac boyunca hicbiri 101 barajini gecemedi';
    END IF;
    RAISE NOTICE
      'TEST_OK[7]: gercek oyunda % bot acti', v_total_opened;
  END;

  RAISE NOTICE '=== BOT + CEZA + EL SAYISI TESTLERI GECTI ===';
END $$;

ROLLBACK;

-- =============================================================================
-- 101 Okey Plus — uçtan uca regresyon/smoke testi (Docker/pgTAP GEREKTİRMEZ)
-- -----------------------------------------------------------------------------
-- ÇALIŞTIRMA:
--   supabase db query --linked --file supabase/tests/manual/okey_smoke_test.sql
--
-- Canlı (linked) veritabanına karşı çalışır, sonunda HER ZAMAN ROLLBACK eder.
-- RULES.md v2.0 (gerçek 101 Okey Plus kuralları) doğrulanır.
--
-- ÖNEMLİ DERS (2026-08-30): İlk sürümde RLS politikası kendi tablosuna
-- baktığı için "infinite recursion" veriyordu ve bu hata YALNIZCA istemcinin
-- yaptığı gibi doğrudan tablo sorgusunda ortaya çıkıyordu (SECURITY DEFINER
-- RPC'ler RLS'i atladığı için testlerde görünmüyordu). Bu yüzden aşağıdaki
-- adım [2] bilerek `SET LOCAL ROLE authenticated` ile gerçek istemci
-- davranışını taklit eder.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_u1 uuid; v_u2 uuid; v_u3 uuid; v_u4 uuid;
  v_profile_count int;
  v_room public.okey_rooms%ROWTYPE;
  v_match public.okey_matches%ROWTYPE;
  v_join record;
  v_dealer smallint;
  v_c0 int; v_c1 int; v_c2 int; v_c3 int; v_total int;
  v_room_visible int; v_seats_visible int; v_own int; v_other int;

  -- Bilinen açılış fixture'ı (okey = sarı 1 olacak; hiçbiri joker değil)
  v_okey        jsonb := '{"color":"yellow","number":1,"isFalseJoker":false}';
  v_run_a       jsonb := '[{"color":"red","number":10,"isFalseJoker":false},{"color":"red","number":11,"isFalseJoker":false},{"color":"red","number":12,"isFalseJoker":false},{"color":"red","number":13,"isFalseJoker":false}]';   -- 46
  v_set_b       jsonb := '[{"color":"blue","number":13,"isFalseJoker":false},{"color":"black","number":13,"isFalseJoker":false},{"color":"yellow","number":13,"isFalseJoker":false}]';                                              -- 39
  v_run_c       jsonb := '[{"color":"blue","number":5,"isFalseJoker":false},{"color":"blue","number":6,"isFalseJoker":false},{"color":"blue","number":7,"isFalseJoker":false}]';                                                    -- 18
  v_low_run     jsonb := '[{"color":"black","number":2,"isFalseJoker":false},{"color":"black","number":3,"isFalseJoker":false},{"color":"black","number":4,"isFalseJoker":false}]';                                                 -- 9
BEGIN
  SELECT count(*) INTO v_profile_count FROM public.profiles;
  IF v_profile_count < 4 THEN
    RAISE EXCEPTION 'TEST_SKIP: en az 4 profiles satırı gerekiyor';
  END IF;
  SELECT id INTO v_u1 FROM public.profiles ORDER BY created_at ASC OFFSET 0 LIMIT 1;
  SELECT id INTO v_u2 FROM public.profiles ORDER BY created_at ASC OFFSET 1 LIMIT 1;
  SELECT id INTO v_u3 FROM public.profiles ORDER BY created_at ASC OFFSET 2 LIMIT 1;
  SELECT id INTO v_u4 FROM public.profiles ORDER BY created_at ASC OFFSET 3 LIMIT 1;

  ----------------------------------------------------------------------------
  -- [1] Oda kur (mod seçimiyle) + 4 oyuncu otur + el başlasın
  ----------------------------------------------------------------------------
  -- MASA SADECE PUANLA AÇILIR: bu test kural motorunu ölçüyor, ekonomiyi
  -- değil. Bu yüzden oda ücreti sıfırlanır ve oyunculara giriş puanı verilir.
  UPDATE public.okey_settings SET room_creation_fee = 0 WHERE id = true;
  PERFORM public.okey_internal_add_points(v_u1, 100000, 'admin_grant', 'smoke:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u2, 100000, 'admin_grant', 'smoke:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u3, 100000, 'admin_grant', 'smoke:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u4, 100000, 'admin_grant', 'smoke:' || gen_random_uuid()::text);

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(false, 'katlamasiz', 'essiz', 'yardimli');
  IF v_room.game_mode <> 'katlamasiz' OR v_room.team_mode <> 'essiz'
     OR v_room.assist_mode <> 'yardimli' THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: oda modlari yazilmadi';
  END IF;

  -- Yardimsiz mod da kabul edilmeli, gecersiz deger reddedilmeli
  DECLARE v_r2 public.okey_rooms%ROWTYPE; BEGIN
    SELECT * INTO v_r2 FROM public.create_okey_room(false, 'katlamali', 'esli', 'yardimsiz');
    IF v_r2.assist_mode <> 'yardimsiz' THEN
      RAISE EXCEPTION 'TEST_FAIL[1]: yardimsiz mod yazilmadi';
    END IF;
    BEGIN
      PERFORM public.create_okey_room(false, 'katlamasiz', 'essiz', 'gecersiz');
      RAISE EXCEPTION 'TEST_FAIL[1]: gecersiz assist_mode kabul edildi!';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE 'APP:invalid_assist_mode%' THEN RAISE; END IF;
    END;
  END;

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
  IF v_room.status <> 'in_progress' THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: el baslamadi (%)', v_room.status;
  END IF;
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_room.current_match_id;
  v_dealer := v_match.dealer_seat;
  RAISE NOTICE 'TEST_OK[1]: oda + 4 oyuncu + el basladi';

  ----------------------------------------------------------------------------
  -- [2] RULES.md §1 — DAĞITIM: başlayana 22, diğerlerine 21, destede 20
  ----------------------------------------------------------------------------
  SELECT tile_count INTO v_c0 FROM public.okey_player_hands WHERE match_id = v_match.id AND seat_no = 0;
  SELECT tile_count INTO v_c1 FROM public.okey_player_hands WHERE match_id = v_match.id AND seat_no = 1;
  SELECT tile_count INTO v_c2 FROM public.okey_player_hands WHERE match_id = v_match.id AND seat_no = 2;
  SELECT tile_count INTO v_c3 FROM public.okey_player_hands WHERE match_id = v_match.id AND seat_no = 3;
  v_total := v_c0 + v_c1 + v_c2 + v_c3;

  IF (CASE v_dealer WHEN 0 THEN v_c0 WHEN 1 THEN v_c1 WHEN 2 THEN v_c2 ELSE v_c3 END) <> 22 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: baslayan oyuncunun 22 tasi yok';
  END IF;
  IF v_total <> 85 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: dagitilan toplam 85 olmali, oldu=%', v_total;
  END IF;
  IF v_match.deck_remaining <> 20 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: destede 20 tas kalmali, kaldi=%', v_match.deck_remaining;
  END IF;
  RAISE NOTICE 'TEST_OK[2]: dagitim 22/21/21/21 = 85, deste 20 (RULES.md §1)';

  ----------------------------------------------------------------------------
  -- [3] RLS — gerçek istemci gibi doğrudan tablo sorguları (recursion regresyonu)
  ----------------------------------------------------------------------------
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT count(*) INTO v_room_visible FROM public.okey_rooms WHERE id = v_room.id;
  SELECT count(*) INTO v_seats_visible FROM public.okey_room_players WHERE room_id = v_room.id;
  SELECT count(*) INTO v_own FROM public.okey_player_hands WHERE match_id = v_match.id AND user_id = v_u1;
  SELECT count(*) INTO v_other FROM public.okey_player_hands WHERE match_id = v_match.id AND user_id = v_u2;
  RESET ROLE;

  IF v_room_visible <> 1 OR v_seats_visible <> 4 THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: RLS altinda oda/koltuklar gorunmuyor (%/%)', v_room_visible, v_seats_visible;
  END IF;
  IF v_own <> 1 THEN RAISE EXCEPTION 'TEST_FAIL[3]: kendi elimi goremiyorum'; END IF;
  IF v_other <> 0 THEN RAISE EXCEPTION 'TEST_FAIL[3]: baskasinin elini gorebiliyorum! RLS ihlali'; END IF;
  RAISE NOTICE 'TEST_OK[3]: RLS dogru, recursion yok';

  ----------------------------------------------------------------------------
  -- [4] RULES.md §3 — EL AÇMA: 101 altı reddedilmeli, 101+ kabul edilmeli
  ----------------------------------------------------------------------------
  UPDATE public.okey_matches
  SET okey_tile = v_okey, turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_match.id;

  UPDATE public.okey_player_hands
  SET tiles = (SELECT jsonb_agg(t) FROM jsonb_array_elements(
        v_run_a || v_set_b || v_run_c || v_low_run) t),
      is_opening_done = false, opened_with_pairs = false
  WHERE match_id = v_match.id AND seat_no = 0;

  PERFORM set_config('request.jwt.claim.sub',
    (SELECT user_id FROM public.okey_room_players WHERE room_id = v_room.id AND seat_no = 0)::text, true);

  -- 9 puanlık tek per ile açmaya çalış -> reddedilmeli
  BEGIN
    PERFORM public.okey_lay_meld(v_match.id, jsonb_build_array(v_low_run), false);
    RAISE EXCEPTION 'TEST_FAIL[4]: 101 alti acilis kabul edildi!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'APP:points_below_threshold%' THEN RAISE; END IF;
  END;

  -- 46 + 39 + 18 = 103 puan ile aç -> kabul edilmeli
  PERFORM public.okey_lay_meld(v_match.id, jsonb_build_array(v_run_a, v_set_b, v_run_c), false);

  IF NOT (SELECT is_opening_done FROM public.okey_player_hands
          WHERE match_id = v_match.id AND seat_no = 0) THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: acilis sonrasi is_opening_done false kaldi';
  END IF;
  IF (SELECT count(*) FROM public.okey_table_melds WHERE match_id = v_match.id) <> 3 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: masaya 3 grup acilmali';
  END IF;
  IF (SELECT highest_opening_points FROM public.okey_matches WHERE id = v_match.id) <> 103 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: highest_opening_points 103 olmali';
  END IF;
  RAISE NOTICE 'TEST_OK[4]: 101 baraji dogru (9 red, 103 kabul), katlamali baraj kaydedildi';

  ----------------------------------------------------------------------------
  -- [5] RULES.md §2 — SERİ 13'TE BİTER (sarma YOK)
  --
  -- KURAL DEĞİŞİKLİĞİ: Önce 12-13-1 geçerliydi. Kullanıcı "11-12-13'ten
  -- sonra sayı gelmez" diyerek sarmayı kaldırdı.
  ----------------------------------------------------------------------------
  IF public.okey_is_valid_run(
      '[{"color":"blue","number":12,"isFalseJoker":false},{"color":"blue","number":13,"isFalseJoker":false},{"color":"blue","number":1,"isFalseJoker":false}]'::jsonb, v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: 12-13-1 gecersiz olmali (sarma kaldirildi)';
  END IF;
  IF public.okey_is_valid_run(
      '[{"color":"blue","number":13,"isFalseJoker":false},{"color":"blue","number":1,"isFalseJoker":false},{"color":"blue","number":2,"isFalseJoker":false}]'::jsonb, v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: 13-1-2 gecersiz olmali';
  END IF;
  IF NOT public.okey_is_valid_run(
      '[{"color":"blue","number":11,"isFalseJoker":false},{"color":"blue","number":12,"isFalseJoker":false},{"color":"blue","number":13,"isFalseJoker":false}]'::jsonb, v_okey) THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: 11-12-13 gecerli olmali';
  END IF;
  IF public.okey_meld_points(
      '[{"color":"blue","number":11,"isFalseJoker":false},{"color":"blue","number":12,"isFalseJoker":false},{"color":"blue","number":13,"isFalseJoker":false}]'::jsonb, v_okey) <> 36 THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: 11-12-13 puani 36 olmali';
  END IF;
  RAISE NOTICE 'TEST_OK[5]: seri 13te biter, sarma yok (RULES.md §2)';

  ----------------------------------------------------------------------------
  -- [6] RULES.md §6/§7 — BİTİŞ: eli boşaltıp son taşı atmak + puanlama
  ----------------------------------------------------------------------------
  DECLARE
    v_last  jsonb := '{"color":"black","number":9,"isFalseJoker":false}';
    v_room2 public.okey_rooms%ROWTYPE;
    v_m2    public.okey_matches%ROWTYPE;
    v_fin   public.okey_matches%ROWTYPE;
    v_w int; v_l int;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    SELECT * INTO v_room2 FROM public.create_okey_room(false, 'katlamasiz', 'essiz');
    PERFORM public.okey_fill_with_bots(v_room2.id);
    SELECT * INTO v_m2 FROM public.okey_matches
      WHERE id = (SELECT current_match_id FROM public.okey_rooms WHERE id = v_room2.id);

    -- Fixture: seat0 el açmış ve elinde tek taş kaldı; diğerleri hiç açmadı
    UPDATE public.okey_matches
    SET okey_tile = v_okey, turn_seat = 0, turn_phase = 'discard'
    WHERE id = v_m2.id;
    UPDATE public.okey_player_hands
    SET tiles = jsonb_build_array(v_last), is_opening_done = true, opened_this_turn = false
    WHERE match_id = v_m2.id AND seat_no = 0;
    UPDATE public.okey_player_hands
    SET tiles = jsonb_build_array('{"color":"red","number":5,"isFalseJoker":false}'::jsonb),
        is_opening_done = false, went_for_pairs = false
    WHERE match_id = v_m2.id AND seat_no <> 0;

    -- Son taşı at -> BİTİŞ
    PERFORM public.okey_take_turn_action(v_m2.id, 'discard', v_last, NULL);

    SELECT * INTO v_fin FROM public.okey_matches WHERE id = v_m2.id;
    IF v_fin.status <> 'finished' OR v_fin.winner_seat <> 0 THEN
      RAISE EXCEPTION 'TEST_FAIL[6]: son tasi atinca bitmedi (status=%, winner=%)', v_fin.status, v_fin.winner_seat;
    END IF;
    IF v_fin.win_type <> 'normal' THEN
      RAISE EXCEPTION 'TEST_FAIL[6]: bitis turu normal olmali, oldu=%', v_fin.win_type;
    END IF;

    SELECT points INTO v_w FROM public.okey_scores_history
      WHERE match_id = v_m2.id AND seat_no = 0;
    IF v_w <> -101 THEN
      RAISE EXCEPTION 'TEST_FAIL[6]: kazanan -101 almali, aldi=%', v_w;
    END IF;

    -- Hiç açmayanlar 202 ceza almalı (bot koltuklarının user_id'si NULL olduğu
    -- için scores_history'ye yazılmaz; doğrudan maç skorundan bakıyoruz)
    v_l := COALESCE((v_fin.scores ->> '1')::int, 0);
    IF v_l <> 202 THEN
      RAISE EXCEPTION 'TEST_FAIL[6]: hic acmayan 202 almali, aldi=%', v_l;
    END IF;
    RAISE NOTICE 'TEST_OK[6]: bitis (son tasi atma) + puanlama dogru (-101 / 202)';
  END;

  ----------------------------------------------------------------------------
  -- [7] RULES.md §7 — ÇARPANLAR: okey ile bitiş cezayı 2 katına çıkarır
  ----------------------------------------------------------------------------
  DECLARE
    v_room3 public.okey_rooms%ROWTYPE;
    v_m3    public.okey_matches%ROWTYPE;
    v_fin3  public.okey_matches%ROWTYPE;
    v_okey_tile_as_last jsonb := '{"color":"yellow","number":1,"isFalseJoker":false}'; -- = okey
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    SELECT * INTO v_room3 FROM public.create_okey_room(false, 'katlamasiz', 'essiz');
    PERFORM public.okey_fill_with_bots(v_room3.id);
    SELECT * INTO v_m3 FROM public.okey_matches
      WHERE id = (SELECT current_match_id FROM public.okey_rooms WHERE id = v_room3.id);

    UPDATE public.okey_matches
    SET okey_tile = v_okey, turn_seat = 0, turn_phase = 'discard'
    WHERE id = v_m3.id;
    UPDATE public.okey_player_hands
    SET tiles = jsonb_build_array(v_okey_tile_as_last), is_opening_done = true, opened_this_turn = false
    WHERE match_id = v_m3.id AND seat_no = 0;
    UPDATE public.okey_player_hands
    SET tiles = '[]'::jsonb, is_opening_done = false, went_for_pairs = true
    WHERE match_id = v_m3.id AND seat_no <> 0;

    PERFORM public.okey_take_turn_action(v_m3.id, 'discard', v_okey_tile_as_last, NULL);

    SELECT * INTO v_fin3 FROM public.okey_matches WHERE id = v_m3.id;
    IF v_fin3.win_type <> 'okey' THEN
      RAISE EXCEPTION 'TEST_FAIL[7]: okey ile bitis etiketi yanlis: %', v_fin3.win_type;
    END IF;
    -- çifte gidip açamayan = 404, okey çarpanı ×2 -> 808
    IF COALESCE((v_fin3.scores ->> '1')::int, 0) <> 808 THEN
      RAISE EXCEPTION 'TEST_FAIL[7]: cifte gidip acamayan + okey carpani 808 olmali, oldu=%',
        (v_fin3.scores ->> '1');
    END IF;
    RAISE NOTICE 'TEST_OK[7]: okey ile bitis carpani (x2) ve 404 cezasi dogru -> 808';
  END;

  ----------------------------------------------------------------------------
  -- [8] RULES.md §5 — EŞLİ mod: eşi açmışsa diğer eş barajsız açar
  ----------------------------------------------------------------------------
  DECLARE
    v_room4 public.okey_rooms%ROWTYPE;
    v_m4    public.okey_matches%ROWTYPE;
    v_req   record;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    SELECT * INTO v_room4 FROM public.create_okey_room(false, 'katlamasiz', 'esli');
    PERFORM public.okey_fill_with_bots(v_room4.id);
    SELECT * INTO v_m4 FROM public.okey_matches
      WHERE id = (SELECT current_match_id FROM public.okey_rooms WHERE id = v_room4.id);

    -- Seat 2 (seat 0'in esi) henuz acmadi -> seat 0 icin baraj 101
    SELECT * INTO v_req FROM public.okey_required_opening(v_m4.id, 0::smallint);
    IF v_req.min_points <> 101 THEN
      RAISE EXCEPTION 'TEST_FAIL[8]: esi acmamisken baraj 101 olmali, oldu=%', v_req.min_points;
    END IF;

    -- Esi (seat 2) acinca seat 0 barajsiz acabilmeli
    UPDATE public.okey_player_hands SET is_opening_done = true
    WHERE match_id = v_m4.id AND seat_no = 2;

    SELECT * INTO v_req FROM public.okey_required_opening(v_m4.id, 0::smallint);
    IF v_req.min_points <> 0 THEN
      RAISE EXCEPTION 'TEST_FAIL[8]: esi acinca baraj 0 olmali, oldu=%', v_req.min_points;
    END IF;
    RAISE NOTICE 'TEST_OK[8]: esli mod — es acinca baraj kalkiyor (RULES.md §5)';
  END;

  ----------------------------------------------------------------------------
  -- [9] RULES.md §5 — KATLAMALI mod: sonraki açılış öncekinden >=1 fazla
  ----------------------------------------------------------------------------
  DECLARE
    v_room5 public.okey_rooms%ROWTYPE;
    v_m5    public.okey_matches%ROWTYPE;
    v_req5  record;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    SELECT * INTO v_room5 FROM public.create_okey_room(false, 'katlamali', 'essiz');
    PERFORM public.okey_fill_with_bots(v_room5.id);
    SELECT * INTO v_m5 FROM public.okey_matches
      WHERE id = (SELECT current_match_id FROM public.okey_rooms WHERE id = v_room5.id);

    SELECT * INTO v_req5 FROM public.okey_required_opening(v_m5.id, 1::smallint);
    IF v_req5.min_points <> 101 OR v_req5.min_pairs <> 5 THEN
      RAISE EXCEPTION 'TEST_FAIL[9]: ilk baraj 101/5 olmali (%/%)', v_req5.min_points, v_req5.min_pairs;
    END IF;

    UPDATE public.okey_matches
    SET highest_opening_points = 103, highest_opening_pairs = 5
    WHERE id = v_m5.id;

    SELECT * INTO v_req5 FROM public.okey_required_opening(v_m5.id, 1::smallint);
    IF v_req5.min_points <> 104 OR v_req5.min_pairs <> 6 THEN
      RAISE EXCEPTION 'TEST_FAIL[9]: katlamali baraj 104/6 olmali (%/%)', v_req5.min_points, v_req5.min_pairs;
    END IF;
    RAISE NOTICE 'TEST_OK[9]: katlamali mod baraji yukseliyor (103->104, 5->6)';
  END;

  ----------------------------------------------------------------------------
  -- [10] Bot akışı: sıra bota gelince otomatik ilerlemeli
  ----------------------------------------------------------------------------
  DECLARE
    v_room6 public.okey_rooms%ROWTYPE;
    v_m6 public.okey_matches%ROWTYPE;
    v_human smallint;
    v_t jsonb;
    i int;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    SELECT * INTO v_room6 FROM public.create_okey_room(false, 'katlamasiz', 'essiz');
    PERFORM public.okey_fill_with_bots(v_room6.id);
    SELECT * INTO v_m6 FROM public.okey_matches
      WHERE id = (SELECT current_match_id FROM public.okey_rooms WHERE id = v_room6.id);
    SELECT seat_no INTO v_human FROM public.okey_room_players
      WHERE room_id = v_room6.id AND user_id = v_u1;

    IF v_m6.turn_seat = v_human AND v_m6.turn_phase = 'discard' THEN
      SELECT tiles -> 0 INTO v_t FROM public.okey_player_hands
        WHERE match_id = v_m6.id AND seat_no = v_human;
      PERFORM public.okey_take_turn_action(v_m6.id, 'discard', v_t, NULL);
    END IF;

    FOR i IN 1..8 LOOP
      SELECT * INTO v_m6 FROM public.okey_matches WHERE id = v_m6.id;
      EXIT WHEN v_m6.turn_seat = v_human OR v_m6.status <> 'in_progress';
      PERFORM public.okey_bot_take_turn(v_m6.id);
    END LOOP;

    SELECT * INTO v_m6 FROM public.okey_matches WHERE id = v_m6.id;
    IF v_m6.status = 'in_progress' AND v_m6.turn_seat <> v_human THEN
      RAISE EXCEPTION 'TEST_FAIL[10]: botlar sirayi insana getirmedi (turn=%)', v_m6.turn_seat;
    END IF;
    RAISE NOTICE 'TEST_OK[10]: bot akisi calisiyor';
  END;

  RAISE NOTICE 'TUM_TESTLER_GECTI';
END;
$$;

ROLLBACK;

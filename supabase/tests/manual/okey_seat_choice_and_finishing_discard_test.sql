-- =============================================================================
-- 101 Okey — KOLTUK SEÇİMİ, ELİ BİTİREN ATIŞ ve ÇİFT AÇANIN ×2 CEZASI
--   supabase db query --linked --file supabase/tests/manual/okey_seat_choice_and_finishing_discard_test.sql
--
-- Kullanıcı 2026-09-21'de dört madde bildirdi; SUNUCUYA bakan üçü burada
-- uçtan uca kanıtlanır (istemci tarafı Dart testlerinde):
--
--   [A] "oyuncular istediği (eşli) kişinin karşısında oturabilsin"
--       → okey_choose_seat: boş koltuğa geçiş, dolu/bot koltuk reddi, hazır
--         işaretinin düşmesi, oturmayanın ve oyun başlamış odanın reddi.
--   [B] "el bittiğinde son taş işlekte işlek sayılmasın"
--       → eli bitiren atış işlek taş cezası yazmaz; bitirmeyen atış YAZAR;
--         OKEY atma cezası bitiş atışında da işler; deste bitişini kapatan
--         atış (kazanan yok) hâlâ cezalıdır.
--   [C] "çift açan kişi elindeki taşlar 2 ile katlanır, taşlar 11 ise 22"
--       → bu kural ZATEN canlıdaydı (okey_internal_finalize_hand); burada
--         kullanıcının verdiği örnekle (11 → 22) sabitlenir, seri açanın
--         11'i ve okeyle bitişte ×2'nin birleşimi (11 → 44) da denenir.
--
-- ## Nasıl okunur
--
-- Betik TEK bir DO bloğudur ve SONUNDA bilerek istisna fırlatır: istisna tüm
-- değişiklikleri geri alır (canlı veriye dokunulmaz) ve mesajı sonucu taşır.
--
--   BAŞARILI:  "TESTS_PASSED ..." ile başlayan bir hata mesajı
--   BAŞARISIZ: "TEST_FAIL[x]: ..." ile başlayan bir hata mesajı
-- =============================================================================

CREATE OR REPLACE FUNCTION pg_temp.t_tile(p_color text, p_number int)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('color', p_color, 'number', p_number, 'isFalseJoker', false)
$$;

CREATE OR REPLACE FUNCTION pg_temp.t_as(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true)
$$;

-- Dört kişilik, 1 elli, KATLAMASIZ/EŞSİZ bir masa kurup eli başlatır.
-- Gösterge mavi 7 => okey mavi 8. Sıra 0. koltukta, ATMA aşamasında.
CREATE OR REPLACE FUNCTION pg_temp.t_new_game(u1 uuid, u2 uuid, u3 uuid, u4 uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_room public.okey_rooms%ROWTYPE;
  v_join record;
BEGIN
  PERFORM pg_temp.t_as(u1);
  SELECT * INTO v_room FROM public.create_okey_room(false, 'katlamasiz', 'essiz', 'yardimli', 1, 100);
  PERFORM pg_temp.t_as(u2);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);
  PERFORM pg_temp.t_as(u3);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);
  PERFORM pg_temp.t_as(u4);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);

  PERFORM pg_temp.t_as(u1); PERFORM public.set_okey_ready(v_room.id, true);
  PERFORM pg_temp.t_as(u2); PERFORM public.set_okey_ready(v_room.id, true);
  PERFORM pg_temp.t_as(u3); PERFORM public.set_okey_ready(v_room.id, true);
  PERFORM pg_temp.t_as(u4); PERFORM public.set_okey_ready(v_room.id, true);

  SELECT * INTO v_room FROM public.okey_rooms WHERE id = v_room.id;
  IF v_room.current_match_id IS NULL THEN
    RAISE EXCEPTION 'TEST_FAIL[setup]: dort kisi hazir oldu ama el baslamadi';
  END IF;

  UPDATE public.okey_matches
  SET indicator_tile = pg_temp.t_tile('blue', 7),
      okey_tile = pg_temp.t_tile('blue', 8),
      turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_room.current_match_id;

  RETURN v_room.current_match_id;
END $$;

-- Bir koltuğun elini AÇIK (seri ya da çiftle) olarak kurar.
CREATE OR REPLACE FUNCTION pg_temp.t_set_hand(
  p_match uuid, p_seat int, p_tiles jsonb,
  p_opened boolean, p_pairs boolean DEFAULT false
) RETURNS void LANGUAGE sql AS $$
  UPDATE public.okey_player_hands
  SET tiles = p_tiles,
      is_opening_done = p_opened,
      opened_with_pairs = p_opened AND p_pairs,
      went_for_pairs = p_opened AND p_pairs,
      opening_points = NULL, opening_pairs = NULL,
      penalty_points = 0, side_draw_tile = NULL, side_draw_count = NULL
  WHERE match_id = p_match AND seat_no = p_seat
$$;

CREATE OR REPLACE FUNCTION pg_temp.t_points(p_match uuid, p_seat int)
RETURNS int LANGUAGE sql AS $$
  SELECT sh.points FROM public.okey_scores_history sh
  WHERE sh.match_id = p_match AND sh.seat_no = p_seat
$$;

DO $$
DECLARE
  v_u1 uuid; v_u2 uuid; v_u3 uuid; v_u4 uuid;
  v_n int;
  v_log text := '';
  v_room public.okey_rooms%ROWTYPE;
  v_join record;
  v_seat smallint;
  v_row public.okey_room_players%ROWTYPE;
  v_joined timestamptz;
  v_match uuid;
  v_status text;
  v_pen int;
  v_err text;
  v_okey jsonb := pg_temp.t_tile('blue', 8);
  v_rest jsonb := jsonb_build_array(pg_temp.t_tile('black', 5), pg_temp.t_tile('blue', 6)); -- toplam 11
BEGIN
  SELECT count(*) INTO v_n FROM public.profiles;
  IF v_n < 4 THEN RAISE EXCEPTION 'TEST_SKIP: 4 profil gerekli'; END IF;
  SELECT id INTO v_u1 FROM public.profiles ORDER BY created_at ASC OFFSET 0 LIMIT 1;
  SELECT id INTO v_u2 FROM public.profiles ORDER BY created_at ASC OFFSET 1 LIMIT 1;
  SELECT id INTO v_u3 FROM public.profiles ORDER BY created_at ASC OFFSET 2 LIMIT 1;
  SELECT id INTO v_u4 FROM public.profiles ORDER BY created_at ASC OFFSET 3 LIMIT 1;

  UPDATE public.okey_settings
  SET room_creation_fee = 0, commission_percent = 0, min_entry_fee = 100,
      mistake_discard_penalty = 101, okey_discard_penalty = 101,
      okey_in_hand_penalty = 101, side_draw_penalty = 101
  WHERE id = true;

  PERFORM public.okey_internal_add_points(v_u1, 100000, 'admin_grant', 'seattest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u2, 100000, 'admin_grant', 'seattest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u3, 100000, 'admin_grant', 'seattest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u4, 100000, 'admin_grant', 'seattest:' || gen_random_uuid()::text);

  ----------------------------------------------------------------------------
  -- [A] KOLTUK SEÇİMİ — EŞLİ masa: 0 (kurucu), 1, 2 oturur; 3 boş.
  ----------------------------------------------------------------------------
  PERFORM pg_temp.t_as(v_u1);
  SELECT * INTO v_room FROM public.create_okey_room(false, 'katlamasiz', 'esli', 'yardimli', 1, 100);
  PERFORM pg_temp.t_as(v_u2);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);
  PERFORM pg_temp.t_as(v_u3);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);

  SELECT rp.joined_at INTO v_joined FROM public.okey_room_players rp
  WHERE rp.room_id = v_room.id AND rp.user_id = v_u2;

  -- [A1] u2 (koltuk 1) boş koltuk 3'e geçer: hazırdı, hazır işareti düşer.
  PERFORM pg_temp.t_as(v_u2);
  PERFORM public.set_okey_ready(v_room.id, true);
  v_seat := public.okey_choose_seat(v_room.id, 3::smallint);
  IF v_seat <> 3 THEN
    RAISE EXCEPTION 'TEST_FAIL[A1]: 3 donmeliydi (% geldi)', v_seat;
  END IF;
  SELECT rp.* INTO v_row FROM public.okey_room_players rp
  WHERE rp.room_id = v_room.id AND rp.seat_no = 3;
  IF v_row.user_id IS DISTINCT FROM v_u2 THEN
    RAISE EXCEPTION 'TEST_FAIL[A1]: koltuk 3 u2 ile dolmadi';
  END IF;
  IF v_row.is_ready THEN
    RAISE EXCEPTION 'TEST_FAIL[A1]: gecis sonrasi hazir isareti dusmedi';
  END IF;
  IF v_row.joined_at IS DISTINCT FROM v_joined THEN
    RAISE EXCEPTION 'TEST_FAIL[A1]: katilma ani tasinmadi';
  END IF;
  SELECT rp.* INTO v_row FROM public.okey_room_players rp
  WHERE rp.room_id = v_room.id AND rp.seat_no = 1;
  IF v_row.user_id IS NOT NULL OR v_row.is_ready OR v_row.is_bot THEN
    RAISE EXCEPTION 'TEST_FAIL[A1]: eski koltuk 1 bosalmadi';
  END IF;
  v_log := v_log || E'\n  [A1] bos koltuga gecis + hazir dustu + katilma ani korundu';

  -- [A2] Başkası oturan koltuk alınamaz (u3, koltuk 0'ı = kurucu).
  PERFORM pg_temp.t_as(v_u3);
  v_err := NULL;
  BEGIN
    PERFORM public.okey_choose_seat(v_room.id, 0::smallint);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  IF v_err IS NULL OR v_err NOT LIKE '%seat_taken%' THEN
    RAISE EXCEPTION 'TEST_FAIL[A2]: dolu koltuk alinabildi (%)', COALESCE(v_err, 'hata yok');
  END IF;
  v_log := v_log || E'\n  [A2] dolu koltuk reddedildi (seat_taken)';

  -- [A3] Geçersiz koltuk numarası.
  v_err := NULL;
  BEGIN
    PERFORM public.okey_choose_seat(v_room.id, 7::smallint);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  IF v_err IS NULL OR v_err NOT LIKE '%invalid_seat%' THEN
    RAISE EXCEPTION 'TEST_FAIL[A3]: gecersiz koltuk kabul edildi (%)', COALESCE(v_err, 'hata yok');
  END IF;
  v_log := v_log || E'\n  [A3] gecersiz koltuk reddedildi';

  -- [A4] Odada OTURMAYAN (u4) koltuk seçemez.
  PERFORM pg_temp.t_as(v_u4);
  v_err := NULL;
  BEGIN
    PERFORM public.okey_choose_seat(v_room.id, 1::smallint);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  IF v_err IS NULL OR v_err NOT LIKE '%not_seated%' THEN
    RAISE EXCEPTION 'TEST_FAIL[A4]: oturmayan koltuk secebildi (%)', COALESCE(v_err, 'hata yok');
  END IF;
  v_log := v_log || E'\n  [A4] oturmayan oyuncu reddedildi';

  -- [A5] Oturum yoksa reddedilir.
  PERFORM pg_temp.t_as(NULL);
  v_err := NULL;
  BEGIN
    PERFORM public.okey_choose_seat(v_room.id, 1::smallint);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  IF v_err IS NULL OR v_err NOT LIKE '%auth_required%' THEN
    RAISE EXCEPTION 'TEST_FAIL[A5]: oturumsuz cagri kabul edildi (%)', COALESCE(v_err, 'hata yok');
  END IF;
  v_log := v_log || E'\n  [A5] oturumsuz cagri reddedildi';

  -- [A6] Aynı koltuğa "geçmek" işlemsizdir ve hazır işaretini KORUR.
  PERFORM pg_temp.t_as(v_u2);
  PERFORM public.set_okey_ready(v_room.id, true);
  v_seat := public.okey_choose_seat(v_room.id, 3::smallint);
  SELECT rp.* INTO v_row FROM public.okey_room_players rp
  WHERE rp.room_id = v_room.id AND rp.seat_no = 3;
  IF v_seat <> 3 OR NOT v_row.is_ready OR v_row.user_id IS DISTINCT FROM v_u2 THEN
    RAISE EXCEPTION 'TEST_FAIL[A6]: ayni koltuga gecis hazir isaretini bozdu';
  END IF;
  v_log := v_log || E'\n  [A6] ayni koltuga gecis islemsiz, hazir korundu';

  -- [A7] BOT koltuğu alınamaz (join_okey_room ile aynı ölçüt).
  UPDATE public.okey_room_players SET is_bot = true, is_ready = true
  WHERE room_id = v_room.id AND seat_no = 1;
  PERFORM pg_temp.t_as(v_u3);
  v_err := NULL;
  BEGIN
    PERFORM public.okey_choose_seat(v_room.id, 1::smallint);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  IF v_err IS NULL OR v_err NOT LIKE '%seat_taken%' THEN
    RAISE EXCEPTION 'TEST_FAIL[A7]: bot koltugu alinabildi (%)', COALESCE(v_err, 'hata yok');
  END IF;
  v_log := v_log || E'\n  [A7] bot koltugu reddedildi';

  -- [A8] Oyun BAŞLAMIŞ odada koltuk değişmez.
  UPDATE public.okey_room_players SET is_bot = false, is_ready = false
  WHERE room_id = v_room.id AND seat_no = 1;
  UPDATE public.okey_rooms SET status = 'in_progress' WHERE id = v_room.id;
  v_err := NULL;
  BEGIN
    PERFORM public.okey_choose_seat(v_room.id, 1::smallint);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  IF v_err IS NULL OR v_err NOT LIKE '%room_not_waiting%' THEN
    RAISE EXCEPTION 'TEST_FAIL[A8]: baslamis odada koltuk degisti (%)', COALESCE(v_err, 'hata yok');
  END IF;
  v_log := v_log || E'\n  [A8] oyun baslamis odada reddedildi';

  UPDATE public.okey_rooms SET status = 'abandoned' WHERE id = v_room.id;

  ----------------------------------------------------------------------------
  -- [B] ELİ BİTİREN ATIŞ İŞLEK SAYILMAZ
  ----------------------------------------------------------------------------

  -- [B1] Elde TEK taş (kırmızı 9), masada kırmızı 10-11-12: taş İŞLEK. Atış eli
  --      bitirir => işlek cezası YOK, kazanan tam -101 alır.
  v_match := pg_temp.t_new_game(v_u1, v_u2, v_u3, v_u4);
  INSERT INTO public.okey_table_melds (match_id, hand_no, laid_by_seat, meld_type, tiles)
  SELECT v_match, m.hand_no, 1, 'run',
         jsonb_build_array(pg_temp.t_tile('red', 10), pg_temp.t_tile('red', 11), pg_temp.t_tile('red', 12))
  FROM public.okey_matches m WHERE m.id = v_match;

  PERFORM pg_temp.t_set_hand(v_match, 0, jsonb_build_array(pg_temp.t_tile('red', 9)), true);
  -- [C] Kalan taşlar toplamı 11: seri açan 11, ÇİFT açan 22, hiç açmayan 202.
  PERFORM pg_temp.t_set_hand(v_match, 1, v_rest, true, false);
  PERFORM pg_temp.t_set_hand(v_match, 2, v_rest, true, true);
  PERFORM pg_temp.t_set_hand(v_match, 3, v_rest, false);

  PERFORM pg_temp.t_as(v_u1);
  PERFORM public.okey_take_turn_action_v2(v_match, 'discard', pg_temp.t_tile('red', 9));

  SELECT m.status INTO v_status FROM public.okey_matches m WHERE m.id = v_match;
  IF v_status <> 'finished' THEN
    RAISE EXCEPTION 'TEST_FAIL[B1]: el bitmedi (%)', v_status;
  END IF;
  SELECT h.penalty_points INTO v_pen FROM public.okey_player_hands h
  WHERE h.match_id = v_match AND h.seat_no = 0;
  IF v_pen <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL[B1]: eli bitiren islek atisa ceza yazildi (%)', v_pen;
  END IF;
  IF pg_temp.t_points(v_match, 0) <> -101 THEN
    RAISE EXCEPTION 'TEST_FAIL[B1]: kazanan -101 almaliydi (% geldi)', pg_temp.t_points(v_match, 0);
  END IF;
  v_log := v_log || E'\n  [B1] eli bitiren islek atis cezasiz, kazanan -101';

  -- [C1] KULLANICININ ÖRNEĞİ: çift açanın kalan taşları 11 => 22.
  IF pg_temp.t_points(v_match, 2) <> 22 THEN
    RAISE EXCEPTION 'TEST_FAIL[C1]: cift acan 11 tasla 22 almaliydi (% geldi)', pg_temp.t_points(v_match, 2);
  END IF;
  -- [C2] Aynı 11, SERİ açanda katlanmaz; hiç açmayan 202.
  IF pg_temp.t_points(v_match, 1) <> 11 THEN
    RAISE EXCEPTION 'TEST_FAIL[C2]: seri acan 11 almaliydi (% geldi)', pg_temp.t_points(v_match, 1);
  END IF;
  IF pg_temp.t_points(v_match, 3) <> 202 THEN
    RAISE EXCEPTION 'TEST_FAIL[C2]: hic acmayan 202 almaliydi (% geldi)', pg_temp.t_points(v_match, 3);
  END IF;
  v_log := v_log || E'\n  [C1] cift acan: kalan taslar 11 => skor 22';
  v_log := v_log || E'\n  [C2] seri acan 11 (katlanmaz), hic acmayan 202';

  -- [B2] Bitirmeyen atışta işlek taş HÂLÂ +101 (elde 2 taş var).
  v_match := pg_temp.t_new_game(v_u1, v_u2, v_u3, v_u4);
  INSERT INTO public.okey_table_melds (match_id, hand_no, laid_by_seat, meld_type, tiles)
  SELECT v_match, m.hand_no, 1, 'run',
         jsonb_build_array(pg_temp.t_tile('red', 10), pg_temp.t_tile('red', 11), pg_temp.t_tile('red', 12))
  FROM public.okey_matches m WHERE m.id = v_match;
  PERFORM pg_temp.t_set_hand(v_match, 0,
    jsonb_build_array(pg_temp.t_tile('red', 9), pg_temp.t_tile('yellow', 5)), true);

  PERFORM pg_temp.t_as(v_u1);
  PERFORM public.okey_take_turn_action_v2(v_match, 'discard', pg_temp.t_tile('red', 9));
  SELECT h.penalty_points INTO v_pen FROM public.okey_player_hands h
  WHERE h.match_id = v_match AND h.seat_no = 0;
  IF v_pen <> 101 THEN
    RAISE EXCEPTION 'TEST_FAIL[B2]: bitirmeyen islek atista +101 yazilmaliydi (% geldi)', v_pen;
  END IF;
  v_log := v_log || E'\n  [B2] bitirmeyen islek atis hala +101';

  -- [B3] ELİ AÇIK OLMAYAN oyuncu tek taşı atarsa el BİTMEZ (bitiş açık el ister):
  --      o atış da işlek cezasına tabidir.
  v_match := pg_temp.t_new_game(v_u1, v_u2, v_u3, v_u4);
  INSERT INTO public.okey_table_melds (match_id, hand_no, laid_by_seat, meld_type, tiles)
  SELECT v_match, m.hand_no, 1, 'run',
         jsonb_build_array(pg_temp.t_tile('red', 10), pg_temp.t_tile('red', 11), pg_temp.t_tile('red', 12))
  FROM public.okey_matches m WHERE m.id = v_match;
  PERFORM pg_temp.t_set_hand(v_match, 0, jsonb_build_array(pg_temp.t_tile('red', 9)), false);
  PERFORM pg_temp.t_as(v_u1);
  PERFORM public.okey_take_turn_action_v2(v_match, 'discard', pg_temp.t_tile('red', 9));
  SELECT h.penalty_points INTO v_pen FROM public.okey_player_hands h
  WHERE h.match_id = v_match AND h.seat_no = 0;
  IF v_pen <> 101 THEN
    RAISE EXCEPTION 'TEST_FAIL[B3]: acilmamis elde islek atis +101 almaliydi (% geldi)', v_pen;
  END IF;
  v_log := v_log || E'\n  [B3] eli acilmamis oyuncunun islek atisi hala +101 (bitis sayilmaz)';

  -- [B4] OKEY ile bitiş: işlek muafiyeti okey atma cezasını KALDIRMAZ ve
  --      bitiş çarpanı (×2) ile çift açanın ×2'si BİRLEŞİR (11 → 44).
  v_match := pg_temp.t_new_game(v_u1, v_u2, v_u3, v_u4);
  PERFORM pg_temp.t_set_hand(v_match, 0, jsonb_build_array(v_okey), true);
  PERFORM pg_temp.t_set_hand(v_match, 1, v_rest, true, false);
  PERFORM pg_temp.t_set_hand(v_match, 2, v_rest, true, true);
  PERFORM pg_temp.t_set_hand(v_match, 3, v_rest, false);
  PERFORM pg_temp.t_as(v_u1);
  PERFORM public.okey_take_turn_action_v2(v_match, 'discard', v_okey);
  SELECT h.penalty_points INTO v_pen FROM public.okey_player_hands h
  WHERE h.match_id = v_match AND h.seat_no = 0;
  IF v_pen <> 101 THEN
    RAISE EXCEPTION 'TEST_FAIL[B4]: okey atma cezasi 101 olmaliydi (% geldi)', v_pen;
  END IF;
  IF pg_temp.t_points(v_match, 0) <> 0 THEN  -- -101 + 101
    RAISE EXCEPTION 'TEST_FAIL[B4]: okeyle bitiren 0 almaliydi (% geldi)', pg_temp.t_points(v_match, 0);
  END IF;
  IF pg_temp.t_points(v_match, 1) <> 22 THEN  -- 11 x2 (okeyle bitis)
    RAISE EXCEPTION 'TEST_FAIL[B4]: seri acan 22 almaliydi (% geldi)', pg_temp.t_points(v_match, 1);
  END IF;
  IF pg_temp.t_points(v_match, 2) <> 44 THEN  -- 11 x2 (cift acan) x2 (okeyle bitis)
    RAISE EXCEPTION 'TEST_FAIL[B4]: cift acan 44 almaliydi (% geldi)', pg_temp.t_points(v_match, 2);
  END IF;
  IF pg_temp.t_points(v_match, 3) <> 404 THEN  -- 202 x2
    RAISE EXCEPTION 'TEST_FAIL[B4]: hic acmayan 404 almaliydi (% geldi)', pg_temp.t_points(v_match, 3);
  END IF;
  v_log := v_log || E'\n  [B4] okeyle bitis: okey cezasi duruyor; carpanlar 11 -> 22 / 44 / 404';

  -- [B5] DESTE BİTİŞİNİ KAPATAN atış (kazanan yok) DEĞİŞMEDİ: elde başka taş
  --      var, seçim oyuncunun; işlek taş hâlâ +101.
  v_match := pg_temp.t_new_game(v_u1, v_u2, v_u3, v_u4);
  INSERT INTO public.okey_table_melds (match_id, hand_no, laid_by_seat, meld_type, tiles)
  SELECT v_match, m.hand_no, 1, 'run',
         jsonb_build_array(pg_temp.t_tile('red', 10), pg_temp.t_tile('red', 11), pg_temp.t_tile('red', 12))
  FROM public.okey_matches m WHERE m.id = v_match;
  UPDATE public.okey_matches SET deck_remaining = 0 WHERE id = v_match;
  PERFORM pg_temp.t_set_hand(v_match, 0,
    jsonb_build_array(pg_temp.t_tile('red', 9), pg_temp.t_tile('yellow', 5)), true);
  PERFORM pg_temp.t_as(v_u1);
  PERFORM public.okey_take_turn_action_v2(v_match, 'discard', pg_temp.t_tile('red', 9));
  SELECT m.status INTO v_status FROM public.okey_matches m WHERE m.id = v_match;
  IF v_status <> 'finished' THEN
    RAISE EXCEPTION 'TEST_FAIL[B5]: deste bitince el kapanmadi (%)', v_status;
  END IF;
  IF pg_temp.t_points(v_match, 0) <> 106 THEN  -- kalan sari 5 + islek 101
    RAISE EXCEPTION 'TEST_FAIL[B5]: deste bitisinde 106 (5 + 101) bekleniyordu (% geldi)', pg_temp.t_points(v_match, 0);
  END IF;
  v_log := v_log || E'\n  [B5] deste bitisini kapatan islek atis hala cezali (degismedi)';

  -- Tüm değişiklikler bu istisnayla GERİ ALINIR; mesaj sonucu taşır.
  RAISE EXCEPTION 'TESTS_PASSED (canli veriye dokunulmadi):%', v_log;
END $$;

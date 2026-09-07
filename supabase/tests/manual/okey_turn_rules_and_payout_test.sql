-- =============================================================================
-- 101 Okey Plus — TUR KURALLARI, OKEY ÇALMA, ÇİFT BEYANI ve POT ÖDEMESİ
--   supabase db query --linked --file supabase/tests/manual/okey_turn_rules_and_payout_test.sql
--
-- Doğrulanan kurallar (hepsi 2026-09-03 düzeltmeleri):
--   [1] okey_lay_meld eli TAMAMEN boşaltamaz (masa kilitlenmesi düzeltmesi)
--   [2] okey_add_to_meld son taşı işleyip bitiremez
--   [3] Otomatik atma (p_is_auto) okey/işlek taş cezası YAZMAZ ve günlüğe
--       'timeout_auto_discard' olarak düşer
--   [4] Yandan çekilen taş o turda kullanılmazsa ceza yazılır
--   [5] Okey çalma çalışır; eli açık olmayan çalamaz
--   [6] "Çifte gidiyorum" beyanı GERİ ALINAMAZ ve çiftle açmanın ön koşuludur
--   [7] Maç bitince POT kazanana ödenir (ekonomi kancası geri bağlandı)
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
  v_pen int;
  v_tiles jsonb;
  v_before bigint;
  v_after bigint;
  v_act text;
BEGIN
  SELECT count(*) INTO v_n FROM public.profiles;
  IF v_n < 4 THEN RAISE EXCEPTION 'TEST_SKIP: 4 profil gerekli'; END IF;
  SELECT id INTO v_u1 FROM public.profiles ORDER BY created_at ASC OFFSET 0 LIMIT 1;
  SELECT id INTO v_u2 FROM public.profiles ORDER BY created_at ASC OFFSET 1 LIMIT 1;
  SELECT id INTO v_u3 FROM public.profiles ORDER BY created_at ASC OFFSET 2 LIMIT 1;
  SELECT id INTO v_u4 FROM public.profiles ORDER BY created_at ASC OFFSET 3 LIMIT 1;

  UPDATE public.okey_settings
  SET room_creation_fee = 0,
      commission_percent = 0,
      min_entry_fee = 100,
      okey_discard_penalty = 101,
      okey_in_hand_penalty = 101,
      mistake_discard_penalty = 101,
      side_draw_penalty = 101
  WHERE id = true;

  PERFORM public.okey_internal_add_points(v_u1, 100000, 'admin_grant',
    'trtest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u2, 100000, 'admin_grant',
    'trtest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u3, 100000, 'admin_grant',
    'trtest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u4, 100000, 'admin_grant',
    'trtest:' || gen_random_uuid()::text);

  -- Gösterge: mavi 7  =>  okey: mavi 8
  v_gosterge := '{"color":"blue","number":7,"isFalseJoker":false}';
  v_okey     := '{"color":"blue","number":8,"isFalseJoker":false}';

  ----------------------------------------------------------------------------
  -- Kurulum: 4 oyuncu, ücretli masa (100 puan), TEK EL
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(
    false, 'katlamasiz', 'essiz', 'yardimli', 1, 100);
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

  UPDATE public.okey_matches
  SET indicator_tile = v_gosterge,
      okey_tile = v_okey,
      turn_seat = 0,
      turn_phase = 'discard'
  WHERE id = v_match.id;
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;

  ----------------------------------------------------------------------------
  -- [1] Eli TAMAMEN yere sermek reddedilmeli
  ----------------------------------------------------------------------------
  -- 3 x (11-12-13) = 108 puan: baraj (101) AŞILIYOR ki testin engellenme sebebi
  -- gerçekten "el boşalıyor" olsun, baraj altı kalmak olmasın.
  UPDATE public.okey_player_hands
  SET tiles = '[
        {"color":"red","number":11,"isFalseJoker":false},
        {"color":"red","number":12,"isFalseJoker":false},
        {"color":"red","number":13,"isFalseJoker":false},
        {"color":"black","number":11,"isFalseJoker":false},
        {"color":"black","number":12,"isFalseJoker":false},
        {"color":"black","number":13,"isFalseJoker":false},
        {"color":"yellow","number":11,"isFalseJoker":false},
        {"color":"yellow","number":12,"isFalseJoker":false},
        {"color":"yellow","number":13,"isFalseJoker":false}
      ]'::jsonb,
      is_opening_done = false,
      opened_with_pairs = false,
      went_for_pairs = false,
      penalty_points = 0,
      side_draw_tile = NULL,
      side_draw_count = NULL
  WHERE match_id = v_match.id AND seat_no = 0;

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  v_blocked := false;
  BEGIN
    PERFORM public.okey_lay_meld(
      v_match.id,
      '[
        [{"color":"red","number":11,"isFalseJoker":false},
         {"color":"red","number":12,"isFalseJoker":false},
         {"color":"red","number":13,"isFalseJoker":false}],
        [{"color":"black","number":11,"isFalseJoker":false},
         {"color":"black","number":12,"isFalseJoker":false},
         {"color":"black","number":13,"isFalseJoker":false}],
        [{"color":"yellow","number":11,"isFalseJoker":false},
         {"color":"yellow","number":12,"isFalseJoker":false},
         {"color":"yellow","number":13,"isFalseJoker":false}]
      ]'::jsonb,
      false);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%must_keep_discard_tile%' THEN v_blocked := true; END IF;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: el tamamen yere serilebildi (masa kilitlenirdi)';
  END IF;

  -- Aynı el, bir taş fazlayla AÇILABİLMELİ
  UPDATE public.okey_player_hands
  SET tiles = tiles || '[{"color":"yellow","number":3,"isFalseJoker":false}]'::jsonb
  WHERE match_id = v_match.id AND seat_no = 0;

  PERFORM public.okey_lay_meld(
    v_match.id,
    '[
      [{"color":"red","number":11,"isFalseJoker":false},
       {"color":"red","number":12,"isFalseJoker":false},
       {"color":"red","number":13,"isFalseJoker":false}],
      [{"color":"black","number":11,"isFalseJoker":false},
       {"color":"black","number":12,"isFalseJoker":false},
       {"color":"black","number":13,"isFalseJoker":false}],
      [{"color":"yellow","number":11,"isFalseJoker":false},
       {"color":"yellow","number":12,"isFalseJoker":false},
       {"color":"yellow","number":13,"isFalseJoker":false}]
    ]'::jsonb,
    false);

  SELECT h.tiles INTO v_tiles FROM public.okey_player_hands h
  WHERE h.match_id = v_match.id AND h.seat_no = 0;
  IF jsonb_array_length(v_tiles) <> 1 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: acilistan sonra elde 1 tas kalmaliydi (% tas)',
      jsonb_array_length(v_tiles);
  END IF;
  RAISE NOTICE 'TEST_OK[1]: eli bosaltan acilis reddedildi, 1 tas birakan acilis gecti';

  ----------------------------------------------------------------------------
  -- [2] Son taşı İŞLEYEREK bitmek reddedilmeli
  ----------------------------------------------------------------------------
  SELECT id INTO v_meld_id FROM public.okey_table_melds
  WHERE match_id = v_match.id AND laid_by_seat = 0 AND meld_type = 'run'
  ORDER BY id LIMIT 1;

  -- Elde tek taş: kırmızı 10 (kırmızı 11-12-13 perinin ALT ucuna işlenebilir)
  UPDATE public.okey_player_hands
  SET tiles = '[{"color":"red","number":10,"isFalseJoker":false}]'::jsonb
  WHERE match_id = v_match.id AND seat_no = 0;

  v_blocked := false;
  BEGIN
    PERFORM public.okey_add_to_meld(
      v_match.id, v_meld_id,
      '{"color":"red","number":10,"isFalseJoker":false}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%must_keep_discard_tile%' THEN v_blocked := true; END IF;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: son tas islenerek bitirilebildi';
  END IF;
  RAISE NOTICE 'TEST_OK[2]: son tasi isleyerek bitis reddedildi';

  ----------------------------------------------------------------------------
  -- [3] Otomatik atma ceza YAZMAZ + 'timeout_auto_discard' loglanır
  ----------------------------------------------------------------------------
  -- Elde okey + işlenebilir taş var; ikisi de otomatik atılsa ceza olmamalı.
  UPDATE public.okey_player_hands
  SET tiles = jsonb_build_array(v_okey,
        '{"color":"red","number":10,"isFalseJoker":false}'::jsonb),
      penalty_points = 0,
      side_draw_tile = NULL,
      side_draw_count = NULL
  WHERE match_id = v_match.id AND seat_no = 0;

  UPDATE public.okey_matches SET turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_match.id;

  PERFORM public.okey_internal_discard_for_seat(v_match.id, 0::smallint, v_okey, true);

  SELECT penalty_points INTO v_pen FROM public.okey_player_hands
  WHERE match_id = v_match.id AND seat_no = 0;
  IF COALESCE(v_pen, 0) <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: otomatik atmada ceza yazildi (%)', v_pen;
  END IF;

  SELECT action INTO v_act FROM public.okey_moves
  WHERE match_id = v_match.id AND seat_no = 0
  ORDER BY id DESC LIMIT 1;
  IF v_act <> 'timeout_auto_discard' THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: otomatik atma % olarak loglandi', v_act;
  END IF;

  -- Aynı hamle ELLE yapılırsa ceza YAZILMALI (karşılaştırma)
  UPDATE public.okey_player_hands
  SET tiles = jsonb_build_array(v_okey,
        '{"color":"yellow","number":3,"isFalseJoker":false}'::jsonb),
      penalty_points = 0
  WHERE match_id = v_match.id AND seat_no = 0;
  UPDATE public.okey_matches SET turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_match.id;

  PERFORM public.okey_internal_discard_for_seat(v_match.id, 0::smallint, v_okey);

  -- Okey masadaki kırmızı 11-12-13 serisinin ALT ucuna işlenebiliyor; buna
  -- rağmen ceza TEK kalmalı (101). Okey atmak daha özel bir kuraldır ve
  -- "işlek taş atma" cezasıyla ÜST ÜSTE BİNMEZ — aksi halde tek hamle 202
  -- ederdi.
  SELECT penalty_points INTO v_pen FROM public.okey_player_hands
  WHERE match_id = v_match.id AND seat_no = 0;
  IF COALESCE(v_pen, 0) <> 101 THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: elle okey atmada ceza 101 olmaliydi (%)', v_pen;
  END IF;
  RAISE NOTICE 'TEST_OK[3]: otomatik atma cezasiz, elle atma cezali (101)';

  ----------------------------------------------------------------------------
  -- [4] Yandan çekilen taş kullanılmazsa ceza
  ----------------------------------------------------------------------------
  UPDATE public.okey_player_hands
  SET tiles = '[
        {"color":"yellow","number":1,"isFalseJoker":false},
        {"color":"yellow","number":2,"isFalseJoker":false},
        {"color":"yellow","number":5,"isFalseJoker":false}
      ]'::jsonb,
      penalty_points = 0,
      -- Sanki bu turda soldan sarı 2 alınmış gibi (elde 1 kopyası var)
      side_draw_tile = '{"color":"yellow","number":2,"isFalseJoker":false}'::jsonb,
      side_draw_count = 1
  WHERE match_id = v_match.id AND seat_no = 0;

  UPDATE public.okey_matches SET turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_match.id;

  -- Sarı 5 atılıyor: alınan sarı 2 hâlâ elde => KULLANILMADI => ceza
  PERFORM public.okey_internal_discard_for_seat(v_match.id, 0::smallint,
    '{"color":"yellow","number":5,"isFalseJoker":false}'::jsonb);

  SELECT penalty_points INTO v_pen FROM public.okey_player_hands
  WHERE match_id = v_match.id AND seat_no = 0;
  IF COALESCE(v_pen, 0) <> 101 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: kullanilmayan yan tas cezasi yazilmadi (%)', v_pen;
  END IF;

  -- Taş KULLANILMIŞSA (elde kalmamışsa) ceza YAZILMAMALI
  UPDATE public.okey_player_hands
  SET tiles = '[
        {"color":"yellow","number":1,"isFalseJoker":false},
        {"color":"yellow","number":5,"isFalseJoker":false}
      ]'::jsonb,
      penalty_points = 0,
      side_draw_tile = '{"color":"yellow","number":2,"isFalseJoker":false}'::jsonb,
      side_draw_count = 1
  WHERE match_id = v_match.id AND seat_no = 0;
  UPDATE public.okey_matches SET turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_match.id;

  PERFORM public.okey_internal_discard_for_seat(v_match.id, 0::smallint,
    '{"color":"yellow","number":5,"isFalseJoker":false}'::jsonb);

  SELECT penalty_points INTO v_pen FROM public.okey_player_hands
  WHERE match_id = v_match.id AND seat_no = 0;
  IF COALESCE(v_pen, 0) <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: kullanilan yan tasa ceza yazildi (%)', v_pen;
  END IF;
  RAISE NOTICE 'TEST_OK[4]: yandan cekilen tas kullanilmazsa cezali, kullanilirsa serbest';

  ----------------------------------------------------------------------------
  -- [5] OKEY ÇALMA
  ----------------------------------------------------------------------------
  -- Masaya okey'li bir seri koy: mavi 3 - mavi 4 - OKEY(mavi 8, joker) => 3-4-5
  DELETE FROM public.okey_table_melds WHERE match_id = v_match.id;
  INSERT INTO public.okey_table_melds
    (match_id, hand_no, laid_by_seat, meld_type, tiles)
  VALUES (v_match.id, v_match.hand_no, 1, 'run',
    jsonb_build_array(
      '{"color":"blue","number":3,"isFalseJoker":false}'::jsonb,
      '{"color":"blue","number":4,"isFalseJoker":false}'::jsonb,
      v_okey))
  RETURNING id INTO v_meld_id;

  -- Eli AÇIK OLMAYAN oyuncu çalamaz
  UPDATE public.okey_player_hands
  SET tiles = '[
        {"color":"blue","number":5,"isFalseJoker":false},
        {"color":"red","number":4,"isFalseJoker":false}
      ]'::jsonb,
      is_opening_done = false
  WHERE match_id = v_match.id AND seat_no = 0;
  UPDATE public.okey_matches SET turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_match.id;

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  v_blocked := false;
  BEGIN
    PERFORM public.okey_steal_joker(v_match.id, v_meld_id,
      '{"color":"blue","number":5,"isFalseJoker":false}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%opening_required%' THEN v_blocked := true; END IF;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: eli acik olmayan oyuncu okey caldi';
  END IF;

  -- Eli açık oyuncu ÇALABİLİR
  UPDATE public.okey_player_hands SET is_opening_done = true
  WHERE match_id = v_match.id AND seat_no = 0;

  PERFORM public.okey_steal_joker(v_match.id, v_meld_id,
    '{"color":"blue","number":5,"isFalseJoker":false}'::jsonb);

  SELECT tiles INTO v_tiles FROM public.okey_table_melds WHERE id = v_meld_id;
  IF v_tiles -> 2 <> '{"color":"blue","number":5,"isFalseJoker":false}'::jsonb THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: perdeki okey mavi 5 ile degistirilmedi (%)', v_tiles;
  END IF;

  SELECT h.tiles INTO v_tiles FROM public.okey_player_hands h
  WHERE h.match_id = v_match.id AND h.seat_no = 0;
  IF NOT (v_tiles @> jsonb_build_array(v_okey)) THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: calinan okey ele gelmedi (%)', v_tiles;
  END IF;
  IF jsonb_array_length(v_tiles) <> 2 THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: el boyutu degisti (%)', jsonb_array_length(v_tiles);
  END IF;

  -- Uymayan taşla çalma reddedilmeli (perde artık joker yok)
  v_blocked := false;
  BEGIN
    PERFORM public.okey_steal_joker(v_match.id, v_meld_id,
      '{"color":"red","number":4,"isFalseJoker":false}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%no_stealable_joker%' THEN v_blocked := true; END IF;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: jokersiz perden calma engellenmedi';
  END IF;
  RAISE NOTICE 'TEST_OK[5]: okey calma calisiyor ve dogru sekilde kisitli';

  ----------------------------------------------------------------------------
  -- [6] "Çifte gidiyorum" beyanı: geri alınamaz + çiftle açmanın ön koşulu
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
      went_for_pairs = false,
      penalty_points = 0,
      side_draw_tile = NULL,
      side_draw_count = NULL
  WHERE match_id = v_match.id AND seat_no = 0;
  UPDATE public.okey_matches SET turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_match.id;

  -- Beyansız çiftle açılamaz
  v_blocked := false;
  BEGIN
    PERFORM public.okey_lay_meld(v_match.id,
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
      ]'::jsonb, true);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%pairs_declaration_required%' THEN v_blocked := true; END IF;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'TEST_FAIL[6]: beyansiz ciftle acilabildi';
  END IF;

  -- Beyan edilir
  PERFORM public.okey_set_went_for_pairs(v_match.id, true);

  -- Geri alınamaz
  v_blocked := false;
  BEGIN
    PERFORM public.okey_set_went_for_pairs(v_match.id, false);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%pairs_declaration_locked%' THEN v_blocked := true; END IF;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'TEST_FAIL[6]: beyan geri alinabildi (404 cezasi anlamsizlasir)';
  END IF;

  -- Beyandan sonra çiftle açılabilir (gösterge çifti dahil 5 çift)
  PERFORM public.okey_lay_meld(v_match.id,
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
    ]'::jsonb, true);

  SELECT count(*)::int INTO v_n FROM public.okey_table_melds
  WHERE match_id = v_match.id AND laid_by_seat = 0;
  IF v_n <> 5 THEN
    RAISE EXCEPTION 'TEST_FAIL[6]: beyandan sonra 5 cift indirilemedi (%)', v_n;
  END IF;
  RAISE NOTICE 'TEST_OK[6]: beyan geri alinamiyor ve ciftle acmanin on kosulu';

  ----------------------------------------------------------------------------
  -- [7] Maç bitince POT kazanana ödenir
  ----------------------------------------------------------------------------
  SELECT w.points INTO v_before FROM public.okey_wallets w WHERE w.user_id = v_u1;

  -- Koltuk 0 son taşını atıp bitirsin; total_hands = 1 olduğu için maç biter.
  UPDATE public.okey_player_hands
  SET tiles = '[{"color":"yellow","number":3,"isFalseJoker":false}]'::jsonb,
      is_opening_done = true,
      opened_with_pairs = false,
      penalty_points = 0,
      side_draw_tile = NULL,
      side_draw_count = NULL
  WHERE match_id = v_match.id AND seat_no = 0;
  UPDATE public.okey_matches SET turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_match.id;

  PERFORM public.okey_internal_discard_for_seat(v_match.id, 0::smallint,
    '{"color":"yellow","number":3,"isFalseJoker":false}'::jsonb);

  SELECT * INTO v_room FROM public.okey_rooms WHERE id = v_room.id;
  IF v_room.status <> 'finished' THEN
    RAISE EXCEPTION 'TEST_FAIL[7]: tek elde mac bitmedi (%)', v_room.status;
  END IF;

  SELECT w.points INTO v_after FROM public.okey_wallets w WHERE w.user_id = v_u1;

  -- 4 insan x 100 giris = 400 brut, komisyon %0 => kazanan 400 almalı
  IF v_after - v_before <> 400 THEN
    RAISE EXCEPTION
      'TEST_FAIL[7]: pot odenmedi/yanlis odendi (fark: %)', v_after - v_before;
  END IF;

  SELECT count(*)::int INTO v_n FROM public.okey_stats WHERE user_id = v_u1;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'TEST_FAIL[7]: istatistik yazilmadi';
  END IF;
  RAISE NOTICE 'TEST_OK[7]: pot kazanana odendi (+400) ve istatistik yazildi';

  ----------------------------------------------------------------------------
  -- [8] BOT ÇİFTLE AÇAR (beyanı taş çekmeden ÖNCE verir)
  ----------------------------------------------------------------------------
  DECLARE
    v_room2 public.okey_rooms%ROWTYPE;
    v_match2 public.okey_matches%ROWTYPE;
    v_bot_seat smallint;
    v_bot public.okey_player_hands%ROWTYPE;
    v_pairs int;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    SELECT * INTO v_room2 FROM public.create_okey_room(
      false, 'katlamasiz', 'essiz', 'yardimli', 3, 100);
    PERFORM public.okey_fill_with_bots(v_room2.id);

    SELECT * INTO v_room2 FROM public.okey_rooms WHERE id = v_room2.id;
    SELECT * INTO v_match2 FROM public.okey_matches
    WHERE id = v_room2.current_match_id;
    IF v_match2.id IS NULL THEN
      RAISE EXCEPTION 'TEST_FAIL[8]: bot masasinda el baslamadi';
    END IF;

    UPDATE public.okey_matches
    SET indicator_tile = v_gosterge, okey_tile = v_okey
    WHERE id = v_match2.id;
    SELECT * INTO v_match2 FROM public.okey_matches WHERE id = v_match2.id;

    SELECT rp.seat_no INTO v_bot_seat FROM public.okey_room_players AS rp
    WHERE rp.room_id = v_room2.id AND rp.is_bot LIMIT 1;

    -- 5 çift + 1 çöp taşı; hiçbir seri/grup yok, yani baraja SERİYLE
    -- ulaşması imkânsız => bot çifte gitmeyi seçmeli.
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
          {"color":"black","number":12,"isFalseJoker":false},
          {"color":"black","number":12,"isFalseJoker":false},
          {"color":"yellow","number":3,"isFalseJoker":false}
        ]'::jsonb,
        is_opening_done = false,
        opened_with_pairs = false,
        went_for_pairs = false,
        penalty_points = 0,
        side_draw_tile = NULL,
        side_draw_count = NULL
    WHERE match_id = v_match2.id AND seat_no = v_bot_seat;

    v_pairs := jsonb_array_length(public.okey_internal_find_pairs(
      (SELECT h.tiles FROM public.okey_player_hands h
       WHERE h.match_id = v_match2.id AND h.seat_no = v_bot_seat),
      v_match2.okey_tile, v_match2.indicator_tile));
    IF v_pairs < 5 THEN
      RAISE EXCEPTION 'TEST_FAIL[8]: cift bulucu % cift buldu (5 bekleniyordu)',
        v_pairs;
    END IF;

    UPDATE public.okey_matches
    SET turn_seat = v_bot_seat, turn_phase = 'draw'
    WHERE id = v_match2.id;

    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    PERFORM public.okey_bot_take_turn(v_match2.id);

    SELECT h.* INTO v_bot FROM public.okey_player_hands h
    WHERE h.match_id = v_match2.id AND h.seat_no = v_bot_seat;

    IF NOT v_bot.went_for_pairs THEN
      RAISE EXCEPTION 'TEST_FAIL[8]: bot cifte gitme beyani vermedi';
    END IF;
    IF NOT v_bot.is_opening_done OR NOT v_bot.opened_with_pairs THEN
      RAISE EXCEPTION 'TEST_FAIL[8]: bot ciftle acmadi (acik: %, cift: %)',
        v_bot.is_opening_done, v_bot.opened_with_pairs;
    END IF;

    SELECT count(*)::int INTO v_n FROM public.okey_table_melds
    WHERE match_id = v_match2.id AND laid_by_seat = v_bot_seat
      AND meld_type IN ('pair', 'gosterge');
    IF v_n < 5 THEN
      RAISE EXCEPTION 'TEST_FAIL[8]: bot % cift indirdi (>=5 bekleniyordu)', v_n;
    END IF;

    -- Bayat tetikleme: yanlış token ile çağrı HİÇBİR ŞEY yapmamalı
    SELECT * INTO v_match2 FROM public.okey_matches WHERE id = v_match2.id;
    DECLARE
      v_moves_before int;
      v_moves_after int;
    BEGIN
      SELECT count(*)::int INTO v_moves_before FROM public.okey_moves
      WHERE match_id = v_match2.id;
      PERFORM public.okey_bot_take_turn(v_match2.id, gen_random_uuid());
      SELECT count(*)::int INTO v_moves_after FROM public.okey_moves
      WHERE match_id = v_match2.id;
      IF v_moves_after <> v_moves_before THEN
        RAISE EXCEPTION
          'TEST_FAIL[8]: bayat token ile bot oynatildi (% -> % hamle)',
          v_moves_before, v_moves_after;
      END IF;
    END;

    RAISE NOTICE 'TEST_OK[8]: bot ciftle acti (% cift) ve bayat token yok sayildi',
      v_n;
  END;

  RAISE NOTICE '=== TUR KURALLARI / OKEY CALMA / CIFT BEYANI / POT TESTLERI GECTI ===';
END $$;

ROLLBACK;

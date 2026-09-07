-- =============================================================================
-- 101 Okey Plus — ANLIK PER PUANI, İŞLEK TAŞ CEZASI ve KATLAMALI BARAJI
--   supabase db query --linked --file supabase/tests/manual/okey_live_points_and_mistake_discard_test.sql
--
-- Kullanıcı 2026-09-05'te üç şikâyet bildirdi; bu dosya bunların SUNUCUYA
-- bakan yüzünü kanıtlar (arayüz tarafı Dart testlerinde):
--
--   [1] "mevcut puan gösterilmiyor"  → okey_matches.open_points per açınca
--       ve taş işleyince GERÇEKTEN büyüyor mu?
--   [3] "kendi takozda işlek atınca işlek sayılmıyor" → masadaki KENDİ perine
--       işlenebilecek taşı atan oyuncuya mistake_discard_penalty yazılıyor mu?
--   [4] "katlamalıda 105 açan biri diğerini 106 olması lazım" →
--       okey_required_opening katlamalı modda en yüksek açılış + 1 veriyor mu?
--
-- Neden bu test yazıldı: üç kural da kodda YAZILIYDI ama hiçbiri uçtan uca
-- doğrulanmamıştı. "Kodda var" ile "canlıda çalışıyor" arasındaki farkı
-- ancak böyle bir koşu kapatır.
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
  v_pen int;
  v_open int;
  v_req record;
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
      mistake_discard_penalty = 101,
      okey_discard_penalty = 101,
      side_draw_penalty = 101
  WHERE id = true;

  PERFORM public.okey_internal_add_points(v_u1, 100000, 'admin_grant', 'lptest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u2, 100000, 'admin_grant', 'lptest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u3, 100000, 'admin_grant', 'lptest:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u4, 100000, 'admin_grant', 'lptest:' || gen_random_uuid()::text);

  -- Gösterge mavi 7 => okey mavi 8. Testteki hiçbir taş mavi değil, yani
  -- hiçbiri joker sayılmaz: cezaların "okey cezası"na kayma riski yok.
  v_gosterge := '{"color":"blue","number":7,"isFalseJoker":false}';
  v_okey     := '{"color":"blue","number":8,"isFalseJoker":false}';

  ----------------------------------------------------------------------------
  -- KURULUM A — katlamasız masa
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(false, 'katlamasiz', 'essiz', 'yardimli', 1, 100);
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
  SET indicator_tile = v_gosterge, okey_tile = v_okey,
      turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_match.id;
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;

  ----------------------------------------------------------------------------
  -- [1] ANLIK PER PUANI — açılış sayacı büyütür
  ----------------------------------------------------------------------------
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
        {"color":"yellow","number":13,"isFalseJoker":false},
        {"color":"red","number":10,"isFalseJoker":false},
        {"color":"yellow","number":5,"isFalseJoker":false}
      ]'::jsonb,
      is_opening_done = false, opened_with_pairs = false, went_for_pairs = false,
      penalty_points = 0, side_draw_tile = NULL, side_draw_count = NULL
  WHERE match_id = v_match.id AND seat_no = 0;

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
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

  SELECT COALESCE((m.open_points ->> '0')::int, 0) INTO v_open
  FROM public.okey_matches m WHERE m.id = v_match.id;
  IF v_open <> 108 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: acilis sonrasi anlik puan 108 olmaliydi (% geldi)', v_open;
  END IF;
  RAISE NOTICE 'TEST_OK[1]: acilis anlik per puanini 108 yazdi';

  ----------------------------------------------------------------------------
  -- [2] ANLIK PER PUANI — İŞLEME de sayacı büyütür (kendi perine)
  ----------------------------------------------------------------------------
  SELECT id INTO v_meld_id FROM public.okey_table_melds
  WHERE match_id = v_match.id AND laid_by_seat = 0 AND meld_type = 'run'
    AND tiles @> '[{"color":"red","number":11,"isFalseJoker":false}]'::jsonb
  ORDER BY id LIMIT 1;

  PERFORM public.okey_add_to_meld(
    v_match.id, v_meld_id,
    '{"color":"red","number":10,"isFalseJoker":false}'::jsonb);

  SELECT COALESCE((m.open_points ->> '0')::int, 0) INTO v_open
  FROM public.okey_matches m WHERE m.id = v_match.id;
  IF v_open <> 118 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: isleme sonrasi anlik puan 118 olmaliydi (% geldi)', v_open;
  END IF;
  RAISE NOTICE 'TEST_OK[2]: isleme anlik per puanini 118 yapti';

  ----------------------------------------------------------------------------
  -- [3] İŞLEK TAŞ ATMA CEZASI — KENDİ perine işlenebilecek taşı atmak
  --     (kullanıcı: "kendi takozda islek atinca islek sayilmiyor")
  ----------------------------------------------------------------------------
  -- Masada seat 0'ın kendi peri: kırmızı 10-11-12-13. Elinde kırmızı 9 var:
  -- perin ALT ucuna işlenebilir, dolayısıyla ATILMASI hatalı hamledir.
  UPDATE public.okey_player_hands
  SET tiles = '[
        {"color":"red","number":9,"isFalseJoker":false},
        {"color":"yellow","number":5,"isFalseJoker":false}
      ]'::jsonb,
      penalty_points = 0, side_draw_tile = NULL, side_draw_count = NULL
  WHERE match_id = v_match.id AND seat_no = 0;

  UPDATE public.okey_matches
  SET turn_seat = 0, turn_phase = 'discard' WHERE id = v_match.id;

  PERFORM public.okey_take_turn_action(
    v_match.id, 'discard',
    '{"color":"red","number":9,"isFalseJoker":false}'::jsonb);

  SELECT h.penalty_points INTO v_pen FROM public.okey_player_hands h
  WHERE h.match_id = v_match.id AND h.seat_no = 0;
  IF COALESCE(v_pen, 0) <> 101 THEN
    RAISE EXCEPTION
      'TEST_FAIL[3]: kendi perine islenebilir tasi atan oyuncuya +101 yazilmadi (ceza=%)',
      COALESCE(v_pen, 0);
  END IF;
  RAISE NOTICE 'TEST_OK[3]: kendi perine islek tasi atmak +101 ceza yazdi';

  ----------------------------------------------------------------------------
  -- [4] KATLAMALI BARAJ — 105 açan varsa sıradakine 106
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(false, 'katlamali', 'essiz', 'yardimli', 1, 100);
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
  SET indicator_tile = v_gosterge, okey_tile = v_okey,
      turn_seat = 0, turn_phase = 'discard'
  WHERE id = v_match.id;

  -- Açmadan ÖNCE baraj 101 olmalı
  SELECT * INTO v_req FROM public.okey_required_opening(v_match.id, 1::smallint);
  IF v_req.min_points <> 101 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: ilk baraj 101 olmaliydi (% geldi)', v_req.min_points;
  END IF;

  -- seat 0, TAM 105 puanla açar: 36 + 36 + 33
  UPDATE public.okey_player_hands
  SET tiles = '[
        {"color":"red","number":11,"isFalseJoker":false},
        {"color":"red","number":12,"isFalseJoker":false},
        {"color":"red","number":13,"isFalseJoker":false},
        {"color":"black","number":11,"isFalseJoker":false},
        {"color":"black","number":12,"isFalseJoker":false},
        {"color":"black","number":13,"isFalseJoker":false},
        {"color":"yellow","number":10,"isFalseJoker":false},
        {"color":"yellow","number":11,"isFalseJoker":false},
        {"color":"yellow","number":12,"isFalseJoker":false},
        {"color":"yellow","number":5,"isFalseJoker":false}
      ]'::jsonb,
      is_opening_done = false, opened_with_pairs = false, went_for_pairs = false,
      penalty_points = 0, side_draw_tile = NULL, side_draw_count = NULL
  WHERE match_id = v_match.id AND seat_no = 0;

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  PERFORM public.okey_lay_meld(
    v_match.id,
    '[
      [{"color":"red","number":11,"isFalseJoker":false},
       {"color":"red","number":12,"isFalseJoker":false},
       {"color":"red","number":13,"isFalseJoker":false}],
      [{"color":"black","number":11,"isFalseJoker":false},
       {"color":"black","number":12,"isFalseJoker":false},
       {"color":"black","number":13,"isFalseJoker":false}],
      [{"color":"yellow","number":10,"isFalseJoker":false},
       {"color":"yellow","number":11,"isFalseJoker":false},
       {"color":"yellow","number":12,"isFalseJoker":false}]
    ]'::jsonb,
    false);

  SELECT COALESCE((m.open_points ->> '0')::int, 0) INTO v_open
  FROM public.okey_matches m WHERE m.id = v_match.id;
  IF v_open <> 105 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: 105 acilis anlik puani 105 olmaliydi (% geldi)', v_open;
  END IF;

  SELECT * INTO v_req FROM public.okey_required_opening(v_match.id, 1::smallint);
  IF v_req.min_points <> 106 THEN
    RAISE EXCEPTION
      'TEST_FAIL[4]: katlamalida 105 acilistan sonra baraj 106 olmaliydi (% geldi)',
      v_req.min_points;
  END IF;
  RAISE NOTICE 'TEST_OK[4]: katlamalida 105 acilis sonrasi baraj 106';

  RAISE NOTICE '=== ANLIK PUAN / ISLEK CEZA / KATLAMALI BARAJ TESTLERI GECTI ===';
END $$;

ROLLBACK;

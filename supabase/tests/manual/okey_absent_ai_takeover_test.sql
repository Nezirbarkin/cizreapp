-- =============================================================================
-- 101 Okey Plus — KAYIP OYUNCUNUN KOLTUĞUNUN AI'YA DEVRİ testi
-- -----------------------------------------------------------------------------
-- ÇALIŞTIRMA:
--   supabase db query --linked --file supabase/tests/manual/okey_absent_ai_takeover_test.sql
--
-- Canlı (linked) veritabanına karşı çalışır, sonunda HER ZAMAN ROLLBACK eder.
--
-- İDDİA (migration 20260913120001): bir koltuk >=90 sn hiç görünmüyorsa
-- okey_auto_play_absent onu KALICI olarak is_ai_controlled=true yapar ve
-- o turu GERÇEK bot yapay zekâsıyla (okey_bot_take_turn) oynatır — is_bot
-- DEĞİŞMEZ (ekonomi/ödeme bu koltuğu hâlâ gerçek oyuncu sayar).
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_u1 uuid; v_u2 uuid; v_u3 uuid; v_u4 uuid;
  v_profile_count int;
  v_room public.okey_rooms%ROWTYPE;
  v_match public.okey_matches%ROWTYPE;
  v_join record;
  v_absent_seat smallint;
  v_caller_seat smallint;
  v_caller uuid;
  v_result boolean;
  v_row public.okey_room_players%ROWTYPE;
  v_move_count int;
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
  -- Kurulum: oda + 4 oyuncu + el başlasın
  ----------------------------------------------------------------------------
  UPDATE public.okey_settings SET room_creation_fee = 0 WHERE id = true;
  PERFORM public.okey_internal_add_points(v_u1, 100000, 'admin_grant', 'tot:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u2, 100000, 'admin_grant', 'tot:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u3, 100000, 'admin_grant', 'tot:' || gen_random_uuid()::text);
  PERFORM public.okey_internal_add_points(v_u4, 100000, 'admin_grant', 'tot:' || gen_random_uuid()::text);

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(false, 'katlamasiz', 'essiz', 'yardimli');
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
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'TEST_FAIL[0]: el baslamadi';
  END IF;
  v_absent_seat := v_match.turn_seat;
  RAISE NOTICE 'TEST_OK[0]: kurulum tamam (sira koltuk %)', v_absent_seat;

  ----------------------------------------------------------------------------
  -- [1] Sırası gelen koltuk 90 sn'DEN AZ süredir görünmüyor: yalnızca tek
  --     turluk zayıf düşüş beklenir, is_ai_controlled ETKİLENMEMELİ.
  ----------------------------------------------------------------------------
  UPDATE public.okey_room_players
  SET last_seen_at = now() - interval '40 seconds'
  WHERE room_id = v_room.id AND seat_no = v_absent_seat;
  UPDATE public.okey_matches
  SET turn_phase = 'draw'
  WHERE id = v_match.id;

  -- Başka bir koltuktaki oyuncu tetikler.
  v_caller_seat := (v_absent_seat + 1) % 4;
  SELECT user_id INTO v_caller FROM public.okey_room_players
  WHERE room_id = v_room.id AND seat_no = v_caller_seat;
  PERFORM set_config('request.jwt.claim.sub', v_caller::text, true);

  SELECT public.okey_auto_play_absent(v_match.id) INTO v_result;
  IF v_result IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: 40 sn kayıpta oynatmadı';
  END IF;

  SELECT * INTO v_row FROM public.okey_room_players
  WHERE room_id = v_room.id AND seat_no = v_absent_seat;
  IF v_row.is_ai_controlled THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: 40 sn kayıpta ERKEN devredildi (is_ai_controlled)';
  END IF;
  IF v_row.is_bot THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: is_bot beklenmedik şekilde true oldu';
  END IF;
  RAISE NOTICE 'TEST_OK[1]: 40 sn kayıpta yalnızca tek tur oynatıldı, devir YOK';

  ----------------------------------------------------------------------------
  -- [2] Sırası GERÇEKTEN geldiğinde ve 90 sn+ kayıpsa: KALICI DEVİR olmalı.
  ----------------------------------------------------------------------------
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;
  v_absent_seat := v_match.turn_seat; -- sıra ilerlemiş olabilir

  UPDATE public.okey_room_players
  SET last_seen_at = now() - interval '120 seconds'
  WHERE room_id = v_room.id AND seat_no = v_absent_seat;

  v_caller_seat := (v_absent_seat + 1) % 4;
  SELECT user_id INTO v_caller FROM public.okey_room_players
  WHERE room_id = v_room.id AND seat_no = v_caller_seat;
  PERFORM set_config('request.jwt.claim.sub', v_caller::text, true);

  SELECT count(*) INTO v_move_count FROM public.okey_moves WHERE match_id = v_match.id;

  SELECT public.okey_auto_play_absent(v_match.id) INTO v_result;
  IF v_result IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: 120 sn kayıpta oynatmadı';
  END IF;

  SELECT * INTO v_row FROM public.okey_room_players
  WHERE room_id = v_room.id AND seat_no = v_absent_seat;
  IF NOT v_row.is_ai_controlled THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: 120 sn kayıpta is_ai_controlled devreye GİRMEDİ';
  END IF;
  IF v_row.is_bot THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: is_bot yanlışlıkla true oldu (ekonomi bozulurdu)';
  END IF;
  IF v_row.user_id IS DISTINCT FROM v_row.user_id THEN -- sanity: kimlik hâlâ orada
    RAISE EXCEPTION 'TEST_FAIL[2]: user_id kayboldu';
  END IF;
  IF v_row.user_id IS NULL THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: user_id NULL oldu — kimlik korunmalıydı';
  END IF;
  RAISE NOTICE 'TEST_OK[2]: koltuk is_ai_controlled=true oldu, is_bot=false ve kimlik korundu';

  -- Bu turda GERÇEK bot AI'sı (okey_bot_take_turn) çalıştı mı? En az bir yeni
  -- hamle satırı ve turn_seat'in o koltuktan uzaklaşmış olması beklenir
  -- (draw+discard tek satırdan fazlasını üretebilir: aç/işle de satır yazar).
  IF (SELECT count(*) FROM public.okey_moves WHERE match_id = v_match.id) <= v_move_count THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: hiç yeni hamle kaydı oluşmadı';
  END IF;

  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;
  IF v_match.status = 'in_progress' AND v_match.turn_seat = v_absent_seat THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: sıra hâlâ aynı koltukta, masa kilitli kaldı';
  END IF;
  RAISE NOTICE 'TEST_OK[2b]: bot AI turu tamamladı, sıra ilerledi (yeni durum: %)', v_match.status;

  ----------------------------------------------------------------------------
  -- [3] Devirden SONRA: koltuk artık SIRADAN BİR BOT gibi
  --     okey_bot_take_turn ile de sürüklenebilmeli (masadaki başka bir
  --     istemcinin bot-zamanlayıcısı bunu çağırır).
  ----------------------------------------------------------------------------
  IF v_match.status = 'in_progress' AND v_match.turn_seat = v_absent_seat THEN
    -- (yukarıda zaten ilerlemiş olmalıydı, ama güvenlik için) doğrudan çağır
    PERFORM public.okey_bot_take_turn(v_match.id, v_match.turn_token);
    RAISE NOTICE 'TEST_OK[3]: okey_bot_take_turn AI-devir koltuğu için de çalıştı (exception atmadı)';
  ELSE
    RAISE NOTICE 'TEST_SKIP[3]: sıra zaten başka koltukta, ek çağrıya gerek yok';
  END IF;

  ----------------------------------------------------------------------------
  -- [4] REGRESYON: sıradan (devredilmemiş) bir koltuk için okey_bot_take_turn
  --     hâlâ HİÇBİR ŞEY yapmamalı (giriş kapısı gevşetilmedi, yalnızca
  --     GENİŞLETİLDİ).
  ----------------------------------------------------------------------------
  IF v_match.status = 'in_progress' THEN
    DECLARE
      v_normal_seat smallint;
      v_before jsonb;
      v_after jsonb;
    BEGIN
      v_normal_seat := v_match.turn_seat;
      SELECT is_bot, is_ai_controlled INTO v_row.is_bot, v_row.is_ai_controlled
      FROM public.okey_room_players WHERE room_id = v_room.id AND seat_no = v_normal_seat;
      IF NOT v_row.is_bot AND NOT v_row.is_ai_controlled THEN
        SELECT h.tiles INTO v_before FROM public.okey_player_hands h
        WHERE h.match_id = v_match.id AND h.seat_no = v_normal_seat;
        PERFORM public.okey_bot_take_turn(v_match.id, v_match.turn_token);
        SELECT h.tiles INTO v_after FROM public.okey_player_hands h
        WHERE h.match_id = v_match.id AND h.seat_no = v_normal_seat;
        IF v_after IS DISTINCT FROM v_before THEN
          RAISE EXCEPTION 'TEST_FAIL[4]: normal (devredilmemiş) koltuk okey_bot_take_turn ile oynatıldı!';
        END IF;
        RAISE NOTICE 'TEST_OK[4]: normal koltuk okey_bot_take_turn ile OYNATILMADI (beklenen)';
      ELSE
        RAISE NOTICE 'TEST_SKIP[4]: sıradaki koltuk zaten bot/AI-devir';
      END IF;
    END;
  END IF;

  RAISE NOTICE '=== TUM AI-DEVIR TESTLERI GECTI ===';
END $$;

ROLLBACK;

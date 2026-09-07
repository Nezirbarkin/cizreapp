-- =============================================================================
-- 101 Okey Plus — SÜRE DOLUNCA OTOMATİK OYNATMA testi
-- -----------------------------------------------------------------------------
-- ÇALIŞTIRMA:
--   supabase db query --linked --file supabase/tests/manual/okey_timeout_autoplay_test.sql
--
-- Canlı (linked) veritabanına karşı çalışır, sonunda HER ZAMAN ROLLBACK eder.
--
-- İSTENEN DAVRANIŞ: süre dolunca desteden taş çekilir ve ÇEKİLEN TAŞ atılır.
-- Bu testin ASIL İDDİASI: oyuncunun ELİ DEĞİŞMEZ.
--
-- Neden bu kadar önemli: fonksiyonun önceki hali desteden çekip elin İLK
-- taşını (`tiles -> 0`) atıyordu. Yani oyuncu, süresi dolduğu için elindeki
-- gerçek bir taşı kaybediyordu — perlerini bozan, sessiz ve ciddi bir hata.
-- Aşağıdaki [2] ve [4] numaralı adımlar tam olarak bunu yakalar.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_u1 uuid; v_u2 uuid; v_u3 uuid; v_u4 uuid;
  v_profile_count int;
  v_room public.okey_rooms%ROWTYPE;
  v_match public.okey_matches%ROWTYPE;
  v_join record;
  v_seat smallint;
  v_hand_before jsonb; v_hand_after jsonb;
  v_deck_before int; v_deck_after int;
  v_pile jsonb; v_top jsonb;
  v_turn_before smallint;
  v_result boolean;
  v_drawn jsonb;
  v_blocked boolean;
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
  -- Masa artık SADECE PUANLA açılır (en az 100); bu test süre mantığını
  -- ölçüyor, ekonomiyi değil — oda ücreti sıfırlanıp oyunculara puan verilir.
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
  RAISE NOTICE 'TEST_OK[0]: kurulum tamam (sira koltuk %)', v_match.turn_seat;

  ----------------------------------------------------------------------------
  -- [1] SÜRE DOLMADAN çağrılırsa HİÇBİR ŞEY yapılmamalı
  --     (istemcinin "süre doldu" beyanına güvenilmediğinin kanıtı)
  ----------------------------------------------------------------------------
  UPDATE public.okey_matches
  SET turn_deadline = now() + interval '60 seconds'
  WHERE id = v_match.id;

  v_turn_before := v_match.turn_seat;
  SELECT h.tiles INTO v_hand_before FROM public.okey_player_hands AS h
  WHERE h.match_id = v_match.id AND h.seat_no = v_turn_before;

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT public.okey_auto_advance(v_match.id) INTO v_result;

  IF v_result IS NOT FALSE THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: sure dolmadan oynatti (%)', v_result;
  END IF;

  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;
  IF v_match.turn_seat <> v_turn_before THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: sure dolmadan sira ilerledi';
  END IF;
  SELECT h.tiles INTO v_hand_after FROM public.okey_player_hands AS h
  WHERE h.match_id = v_match.id AND h.seat_no = v_turn_before;
  IF v_hand_after <> v_hand_before THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: sure dolmadan el degisti';
  END IF;
  RAISE NOTICE 'TEST_OK[1]: sure dolmadan hicbir sey yapilmadi';

  ----------------------------------------------------------------------------
  -- [2] ÇEKME AŞAMASI + süre doldu
  --     -> desteden çekilir, ÇEKİLEN TAŞ atılır, EL DEĞİŞMEZ
  ----------------------------------------------------------------------------
  UPDATE public.okey_matches
  SET turn_phase = 'draw', turn_deadline = now() - interval '1 second'
  WHERE id = v_match.id;
  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;

  v_seat := v_match.turn_seat;
  v_deck_before := v_match.deck_remaining;
  SELECT h.tiles INTO v_hand_before FROM public.okey_player_hands AS h
  WHERE h.match_id = v_match.id AND h.seat_no = v_seat;

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT public.okey_auto_advance(v_match.id) INTO v_result;
  IF v_result IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: sure doldugu halde oynanmadi';
  END IF;

  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;
  SELECT h.tiles INTO v_hand_after FROM public.okey_player_hands AS h
  WHERE h.match_id = v_match.id AND h.seat_no = v_seat;
  v_deck_after := v_match.deck_remaining;

  -- ASIL İDDİA: el AYNI TAŞLARDAN oluşmalı.
  --
  -- Karşılaştırma SIRADAN BAĞIMSIZ yapılır: çekilen taş elde zaten varsa
  -- (aynı taştan 2 kopya vardır) atma işlemi ilk eşleşeni siler ve dizinin
  -- SIRASI değişir, içeriği değil. Doğrudan jsonb eşitliği bu durumda
  -- yanlışlıkla "el değişti" derdi.
  IF (SELECT array_agg(x ORDER BY x::text)
      FROM jsonb_array_elements(v_hand_after) AS x)
     IS DISTINCT FROM
     (SELECT array_agg(x ORDER BY x::text)
      FROM jsonb_array_elements(v_hand_before) AS x) THEN
    RAISE EXCEPTION
      'TEST_FAIL[2]: EL DEGISTI! oncesi=% sonrasi=%', v_hand_before, v_hand_after;
  END IF;

  -- Desteden bir taş eksilmiş olmalı
  IF v_deck_after <> v_deck_before - 1 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: deste % -> % (1 eksilmeliydi)',
      v_deck_before, v_deck_after;
  END IF;

  -- Iskartanın en üstündeki taş, az önce desteden çekilen taş olmalı
  SELECT mv.tile INTO v_drawn FROM public.okey_moves AS mv
  WHERE mv.match_id = v_match.id AND mv.seat_no = v_seat
    AND mv.action = 'draw_deck'
  ORDER BY mv.id DESC LIMIT 1;

  v_pile := v_match.discard_piles -> v_seat::text;
  v_top := v_pile -> (jsonb_array_length(v_pile) - 1);
  IF v_top IS DISTINCT FROM v_drawn THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: atilan taş cekilen taş degil (cekilen=% atilan=%)',
      v_drawn, v_top;
  END IF;

  -- Sıra ilerlemiş olmalı
  IF v_match.turn_seat = v_seat THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: sira ilerlemedi, masa kilitli kalir';
  END IF;
  RAISE NOTICE 'TEST_OK[2]: cekildi + cekilen atildi + EL DEGISMEDI';

  ----------------------------------------------------------------------------
  -- [3] Süre dolumu YENİ sıra için sıfırlanmalı (art arda kilitlenmemeli)
  ----------------------------------------------------------------------------
  IF v_match.turn_deadline IS NULL OR v_match.turn_deadline <= now() THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: yeni sira icin sure verilmedi';
  END IF;
  RAISE NOTICE 'TEST_OK[3]: yeni siraya taze sure verildi';

  ----------------------------------------------------------------------------
  -- [4] ATMA AŞAMASI + süre doldu
  --     -> bu turda ÇEKİLEN taş atılır, elin geri kalanı korunur
  ----------------------------------------------------------------------------
  v_seat := v_match.turn_seat;

  -- Oyuncu taşını çeksin (ama atmasın)
  v_drawn := public.okey_internal_draw_for_seat(v_match.id, v_seat, 'deck');
  IF v_drawn IS NULL THEN
    RAISE EXCEPTION 'TEST_SKIP[4]: deste bitti';
  END IF;

  SELECT h.tiles INTO v_hand_before FROM public.okey_player_hands AS h
  WHERE h.match_id = v_match.id AND h.seat_no = v_seat;

  -- Süresi dolsun
  UPDATE public.okey_matches
  SET turn_deadline = now() - interval '1 second'
  WHERE id = v_match.id;

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT public.okey_auto_advance(v_match.id) INTO v_result;
  IF v_result IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: atma asamasinda oynanmadi';
  END IF;

  SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;
  SELECT h.tiles INTO v_hand_after FROM public.okey_player_hands AS h
  WHERE h.match_id = v_match.id AND h.seat_no = v_seat;

  -- Atılan taş, bu turda çekilen taş olmalı
  v_pile := v_match.discard_piles -> v_seat::text;
  v_top := v_pile -> (jsonb_array_length(v_pile) - 1);
  IF v_top IS DISTINCT FROM v_drawn THEN
    RAISE EXCEPTION
      'TEST_FAIL[4]: cektigi tas yerine baska tas atildi (cekilen=% atilan=%)',
      v_drawn, v_top;
  END IF;

  -- El, çekmeden önceki haline dönmüş olmalı (bir taş eksilmiş)
  IF jsonb_array_length(v_hand_after) <> jsonb_array_length(v_hand_before) - 1 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: el boyutu beklenmedik (% -> %)',
      jsonb_array_length(v_hand_before), jsonb_array_length(v_hand_after);
  END IF;
  RAISE NOTICE 'TEST_OK[4]: atma asamasinda da CEKTIGI tas atildi';

  ----------------------------------------------------------------------------
  -- [5] Masada OTURMAYAN biri tetikleyemez
  ----------------------------------------------------------------------------
  UPDATE public.okey_matches
  SET turn_deadline = now() - interval '1 second'
  WHERE id = v_match.id;

  DECLARE
    v_outsider uuid;
  BEGIN
    SELECT id INTO v_outsider FROM public.profiles
    WHERE id NOT IN (v_u1, v_u2, v_u3, v_u4) LIMIT 1;

    IF v_outsider IS NULL THEN
      RAISE NOTICE 'TEST_SKIP[5]: masada olmayan 5. profil yok';
    ELSE
      v_blocked := false;
      PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
      BEGIN
        PERFORM public.okey_auto_advance(v_match.id);
      EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'APP:not_seated%' THEN
          v_blocked := true;
        ELSE
          RAISE;
        END IF;
      END;
      IF NOT v_blocked THEN
        RAISE EXCEPTION 'TEST_FAIL[5]: masada olmayan biri sirayi oynatti';
      END IF;
      RAISE NOTICE 'TEST_OK[5]: masada olmayan tetikleyemedi';
    END IF;
  END;

  ----------------------------------------------------------------------------
  -- [6] SÜRE DOLMADAN taş atmak SERBEST olmalı
  --
  -- Kullanıcı "süre bitmeden taş atamıyorum" diye bildirdi. Sebebin sunucuda
  -- bir süre kısıtı OLMADIĞINI burada kalıcı olarak sabitliyoruz: sorun
  -- istemcideydi (eşzamanlı hamle koruması, kullanıcının atma hamlesini
  -- sessizce çöpe atıyordu). Sunucuya ileride yanlışlıkla bir süre kapısı
  -- eklenirse bu test düşer.
  ----------------------------------------------------------------------------
  DECLARE
    v_seat6 smallint;
    v_before6 int;
    v_after6 int;
    v_tile6 jsonb;
  BEGIN
    -- Bol süresi olan taze bir sıra kur
    UPDATE public.okey_matches
    SET turn_phase = 'draw',
        turn_deadline = now() + interval '60 seconds'
    WHERE id = v_match.id;
    SELECT * INTO v_match FROM public.okey_matches WHERE id = v_match.id;

    v_seat6 := v_match.turn_seat;

    IF v_match.deck_remaining > 0 THEN
      PERFORM public.okey_internal_draw_for_seat(v_match.id, v_seat6, 'deck');

      SELECT h.tiles INTO v_tile6 FROM public.okey_player_hands h
      WHERE h.match_id = v_match.id AND h.seat_no = v_seat6;

      IF v_tile6 IS NOT NULL AND jsonb_array_length(v_tile6) > 0 THEN
        SELECT jsonb_array_length(h.tiles) INTO v_before6
        FROM public.okey_player_hands h
        WHERE h.match_id = v_match.id AND h.seat_no = v_seat6;

        -- Süre HENÜZ DOLMADI; atma yine de çalışmalı
        PERFORM public.okey_internal_discard_for_seat(
          v_match.id, v_seat6, v_tile6 -> 0);

        SELECT jsonb_array_length(h.tiles) INTO v_after6
        FROM public.okey_player_hands h
        WHERE h.match_id = v_match.id AND h.seat_no = v_seat6;

        IF v_after6 IS DISTINCT FROM v_before6 - 1 THEN
          RAISE EXCEPTION
            'TEST_FAIL[6]: sure dolmadan atma calismadi (% -> %)',
            v_before6, v_after6;
        END IF;
        RAISE NOTICE 'TEST_OK[6]: sure dolmadan tas atmak serbest';
      END IF;
    ELSE
      RAISE NOTICE 'TEST_SKIP[6]: deste bitti';
    END IF;
  END;

  RAISE NOTICE '=== TUM SURE DOLUMU TESTLERI GECTI ===';
END $$;

ROLLBACK;

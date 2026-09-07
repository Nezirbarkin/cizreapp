-- =============================================================================
-- 101 Okey Plus — MASA SADECE PUANLA AÇILIR (en az 100)
--   supabase db query --linked --file supabase/tests/manual/okey_min_entry_fee_test.sql
--
-- Doğrulanan kurallar:
--   [1] Ücretsiz masa (0 puan) AÇILAMAZ
--   [2] Alt sınırın altındaki masa AÇILAMAZ
--   [3] Alt sınır ve üstü AÇILABİLİR ve oda puanı kaydeder
--   [4] Ücretli masaya girmek için YETERLİ PUAN gerekir
--   [5] El başlarken giriş puanları tahsil edilir
--   [6] Maç bitince pot kazanana ödenir (komisyon düşülerek)
--   [7] Maçı BİTMİŞ oda "devam eden oyunum" sayılmaz
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_u1 uuid; v_u2 uuid; v_u3 uuid; v_u4 uuid;
  v_n int;
  v_min int;
  v_room public.okey_rooms%ROWTYPE;
  v_join record;
  v_blocked boolean;
  v_before bigint; v_after bigint;
  v_seat_of uuid[]; v_i int; v_uid uuid; v_pts bigint;
  v_scores jsonb;
BEGIN
  SELECT count(*) INTO v_n FROM public.profiles;
  IF v_n < 4 THEN RAISE EXCEPTION 'TEST_SKIP: 4 profil gerekli'; END IF;
  SELECT id INTO v_u1 FROM public.profiles ORDER BY created_at ASC OFFSET 0 LIMIT 1;
  SELECT id INTO v_u2 FROM public.profiles ORDER BY created_at ASC OFFSET 1 LIMIT 1;
  SELECT id INTO v_u3 FROM public.profiles ORDER BY created_at ASC OFFSET 2 LIMIT 1;
  SELECT id INTO v_u4 FROM public.profiles ORDER BY created_at ASC OFFSET 3 LIMIT 1;

  UPDATE public.okey_settings
  SET room_creation_fee = 0, commission_percent = 10, min_entry_fee = 100
  WHERE id = true;

  SELECT min_entry_fee INTO v_min FROM public.okey_settings WHERE id = true;

  -- Herkese bol puan
  FOR v_i IN 1 .. 4 LOOP
    PERFORM public.okey_internal_add_points(
      CASE v_i WHEN 1 THEN v_u1 WHEN 2 THEN v_u2 WHEN 3 THEN v_u3 ELSE v_u4 END,
      100000, 'admin_grant', 'minfee:' || gen_random_uuid()::text);
  END LOOP;

  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);

  ----------------------------------------------------------------------------
  -- [1] ÜCRETSİZ masa açılamaz
  ----------------------------------------------------------------------------
  v_blocked := false;
  BEGIN
    PERFORM public.create_okey_room(
      false, 'katlamasiz', 'essiz', 'yardimli', 3, 0);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'APP:entry_fee_too_low%' THEN v_blocked := true; ELSE RAISE; END IF;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: UCRETSIZ masa acildi!';
  END IF;
  RAISE NOTICE 'TEST_OK[1]: ucretsiz masa acilamiyor';

  ----------------------------------------------------------------------------
  -- [2] Alt sınırın ALTI açılamaz
  ----------------------------------------------------------------------------
  v_blocked := false;
  BEGIN
    PERFORM public.create_okey_room(
      false, 'katlamasiz', 'essiz', 'yardimli', 3, v_min - 1);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'APP:entry_fee_too_low%' THEN v_blocked := true; ELSE RAISE; END IF;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: alt sinirin altinda masa acildi!';
  END IF;
  RAISE NOTICE 'TEST_OK[2]: alt sinirin alti reddediliyor (min=%)', v_min;

  ----------------------------------------------------------------------------
  -- [3] Alt sınır ve üstü açılabilir
  ----------------------------------------------------------------------------
  SELECT * INTO v_room FROM public.create_okey_room(
    false, 'katlamasiz', 'essiz', 'yardimli', 3, v_min);
  IF v_room.entry_fee <> v_min THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: masa puani kaydedilmedi (%)', v_room.entry_fee;
  END IF;
  RAISE NOTICE 'TEST_OK[3]: % puanli masa acildi', v_room.entry_fee;

  ----------------------------------------------------------------------------
  -- [4] Yetersiz puanla ÜCRETLİ masaya girilemez
  ----------------------------------------------------------------------------
  DECLARE
    v_pricey public.okey_rooms%ROWTYPE;
    v_poor_balance bigint;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    SELECT * INTO v_pricey FROM public.create_okey_room(
      false, 'katlamasiz', 'essiz', 'yardimli', 3, 50000);

    -- v_u2'nin bakiyesini giris ucretinin ALTINA cek
    SELECT points INTO v_poor_balance FROM public.okey_wallets WHERE user_id = v_u2;
    PERFORM public.okey_internal_add_points(
      v_u2, -(v_poor_balance - 10), 'admin_grant',
      'drain:' || gen_random_uuid()::text);

    PERFORM set_config('request.jwt.claim.sub', v_u2::text, true);
    v_blocked := false;
    BEGIN
      PERFORM public.join_okey_room(v_pricey.id, NULL);
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'APP:insufficient_points%' THEN
        v_blocked := true;
      ELSE
        RAISE;
      END IF;
    END;
    IF NOT v_blocked THEN
      RAISE EXCEPTION 'TEST_FAIL[4]: yetersiz puanla ucretli masaya girildi!';
    END IF;
    RAISE NOTICE 'TEST_OK[4]: yetersiz puanla girilemiyor';

    -- Bakiyeyi geri ver
    PERFORM public.okey_internal_add_points(
      v_u2, 100000, 'admin_grant', 'refill:' || gen_random_uuid()::text);
  END;

  ----------------------------------------------------------------------------
  -- [5] El başlarken giriş puanları TAHSİL edilir
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_u2::text, true);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);
  PERFORM set_config('request.jwt.claim.sub', v_u3::text, true);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);
  PERFORM set_config('request.jwt.claim.sub', v_u4::text, true);
  SELECT * INTO v_join FROM public.join_okey_room(v_room.id, NULL);

  SELECT points INTO v_before FROM public.okey_wallets WHERE user_id = v_u1;

  PERFORM public.okey_internal_collect_entry_fees(v_room.id);

  SELECT points INTO v_after FROM public.okey_wallets WHERE user_id = v_u1;
  IF v_before - v_after <> v_min THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: giris ucreti tahsil edilmedi (% -> %)',
      v_before, v_after;
  END IF;
  RAISE NOTICE 'TEST_OK[5]: giris ucreti tahsil edildi';

  ----------------------------------------------------------------------------
  -- [6] Maç bitince POT kazanana ödenir (komisyon düşülerek)
  ----------------------------------------------------------------------------
  v_seat_of := ARRAY[NULL, NULL, NULL, NULL]::uuid[];
  FOR v_i IN 0 .. 3 LOOP
    SELECT rp.user_id INTO v_uid FROM public.okey_room_players rp
    WHERE rp.room_id = v_room.id AND rp.seat_no = v_i;
    v_seat_of[v_i + 1] := v_uid;
  END LOOP;

  SELECT points INTO v_before FROM public.okey_wallets
  WHERE user_id = v_seat_of[2]; -- koltuk 1 kazanacak

  v_scores := jsonb_build_object('0', 150, '1', -101, '2', 200, '3', 180);
  PERFORM public.okey_internal_award_match(v_room.id, v_scores);

  SELECT points INTO v_after FROM public.okey_wallets
  WHERE user_id = v_seat_of[2];

  -- Brut pot = 100 x 4 = 400 ; komisyon %10 = 40 ; net = 360
  IF v_after - v_before <> 360 THEN
    RAISE EXCEPTION
      'TEST_FAIL[6]: kazanan net potu (360) almadi (fark=%)', v_after - v_before;
  END IF;
  RAISE NOTICE 'TEST_OK[6]: kazanan net potu aldi (400 - 40 komisyon = 360)';

  ----------------------------------------------------------------------------
  -- [7] Maçı BİTMİŞ oda "devam eden oyunum" sayılmaz
  ----------------------------------------------------------------------------
  DECLARE
    v_r3 public.okey_rooms%ROWTYPE;
    v_m3 public.okey_matches%ROWTYPE;
    v_active int;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    SELECT * INTO v_r3 FROM public.create_okey_room(
      false, 'katlamasiz', 'essiz', 'yardimli', 5, v_min);
    PERFORM public.okey_fill_with_bots(v_r3.id);

    SELECT * INTO v_r3 FROM public.okey_rooms WHERE id = v_r3.id;
    SELECT * INTO v_m3 FROM public.okey_matches WHERE id = v_r3.current_match_id;

    -- Maçı bitir ama odayı AÇIK bırak (ölü masa senaryosu)
    UPDATE public.okey_matches SET status = 'finished' WHERE id = v_m3.id;
    UPDATE public.okey_rooms SET status = 'in_progress' WHERE id = v_r3.id;

    SELECT count(*)::int INTO v_active
    FROM public.okey_my_active_room() AS r WHERE r.id = v_r3.id;

    IF v_active <> 0 THEN
      RAISE EXCEPTION
        'TEST_FAIL[7]: maci bitmis oda hala "devam eden oyun" sayiliyor';
    END IF;
    RAISE NOTICE 'TEST_OK[7]: maci bitmis oda devam eden sayilmiyor';

    -- Temizlik onu kapatmalı
    PERFORM public.okey_cleanup_stale_rooms();
    SELECT * INTO v_r3 FROM public.okey_rooms WHERE id = v_r3.id;
    IF v_r3.status <> 'finished' THEN
      RAISE EXCEPTION 'TEST_FAIL[7b]: olu masa temizlenmedi (%)', v_r3.status;
    END IF;
    RAISE NOTICE 'TEST_OK[7b]: olu masa temizlendi';
  END;

  RAISE NOTICE '=== MASA PUANI TESTLERI GECTI ===';
END $$;

ROLLBACK;

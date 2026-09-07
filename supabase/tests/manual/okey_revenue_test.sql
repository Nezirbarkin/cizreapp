-- =============================================================================
-- 101 Okey Plus — SİSTEM KAZANCI: oda kurma ücreti + pot komisyonu
--   supabase db query --linked --file supabase/tests/manual/okey_revenue_test.sql
--
-- TARİHÇE: Bahis bir süre tamamen kaldırılmıştı ve bu test "hiçbir puan
-- hareketi olmuyor"u doğruluyordu. Kullanıcı isteğiyle masa puanı geri geldi
-- ve artık ZORUNLU (en az 100). Dolayısıyla iki gelir kalemi de geri döndü.
--
-- Senaryo: 4 GERÇEK oyuncu, 100 giriş puanı, %10 komisyon, 50 oda ücreti
--   Oda kurma      : kurucudan 50 (sistem kazancı)
--   Brüt pot       : 100 x 4 = 400
--   Komisyon %10   : 40      (sistem kazancı)
--   Net pot        : 360     -> kazanana
--   Toplam sistem  : 50 + 40 = 90
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_users uuid[]; v_room public.okey_rooms%ROWTYPE;
  v_seat_of uuid[]; v_i int; v_uid uuid; v_pts bigint;
  v_creator_before bigint; v_creator_after bigint;
  v_before bigint[]; v_after bigint[]; v_scores jsonb;
  v_rev bigint; v_rev_room bigint; v_rev_comm bigint;
  v_row public.okey_settings%ROWTYPE;
BEGIN
  SELECT array_agg(id) INTO v_users FROM (
    SELECT id FROM public.profiles ORDER BY created_at ASC LIMIT 4) t;
  IF array_length(v_users, 1) < 4 THEN
    RAISE EXCEPTION 'TEST_SKIP: 4 kullanici gerekli';
  END IF;

  -- Test ayarlari: 50 oda ucreti, %10 komisyon
  UPDATE public.okey_settings
  SET room_creation_fee = 50, commission_percent = 10 WHERE id = true;

  FOR v_i IN 1..4 LOOP
    PERFORM public.okey_internal_add_points(
      v_users[v_i], 10000, 'admin_grant',
      'revtest:' || v_users[v_i]::text || ':' || gen_random_uuid()::text);
  END LOOP;

  ----------------------------------------------------------------------------
  -- [1] Oda kurma ücreti kurucudan düşülür ve sistem kazancına yazılır
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_users[1]::text, true);
  SELECT points INTO v_creator_before FROM public.okey_wallets WHERE user_id = v_users[1];

  SELECT * INTO v_room FROM public.create_okey_room(false,'katlamasiz','essiz','yardimli',3,100);

  SELECT points INTO v_creator_after FROM public.okey_wallets WHERE user_id = v_users[1];
  IF v_creator_before - v_creator_after <> 50 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: oda kurma ucreti 50 dusulmedi (fark=%)',
      v_creator_before - v_creator_after;
  END IF;

  SELECT COALESCE(sum(amount), 0) INTO v_rev_room
  FROM public.okey_house_revenue
  WHERE source = 'room_fee' AND room_id = v_room.id;
  IF v_rev_room <> 50 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: oda ucreti sistem kazancina yazilmadi (%)', v_rev_room;
  END IF;
  RAISE NOTICE 'TEST_OK[1]: oda kurma ucreti 50 dusuldu ve kazanca yazildi';

  ----------------------------------------------------------------------------
  -- [2] Masaya KATILMAK anında puan düşmez — tahsilat el başında olur
  ----------------------------------------------------------------------------
  v_before := ARRAY[]::bigint[];
  FOR v_i IN 2..4 LOOP
    SELECT points INTO v_pts FROM public.okey_wallets WHERE user_id = v_users[v_i];
    v_before := v_before || v_pts;
  END LOOP;

  FOR v_i IN 2..4 LOOP
    PERFORM set_config('request.jwt.claim.sub', v_users[v_i]::text, true);
    PERFORM public.join_okey_room(v_room.id, NULL);
  END LOOP;

  FOR v_i IN 2..4 LOOP
    SELECT points INTO v_pts FROM public.okey_wallets WHERE user_id = v_users[v_i];
    IF v_pts <> v_before[v_i - 1] THEN
      RAISE EXCEPTION
        'TEST_FAIL[2]: katilirken puan dusuldu (kullanici %: % -> %)',
        v_i, v_before[v_i - 1], v_pts;
    END IF;
  END LOOP;
  RAISE NOTICE 'TEST_OK[2]: katilma aninda puan dusmuyor (tahsilat el basinda)';

  ----------------------------------------------------------------------------
  -- [3] El başlarken giriş puanları TAHSİL edilir
  ----------------------------------------------------------------------------
  v_seat_of := ARRAY[NULL, NULL, NULL, NULL]::uuid[];
  FOR v_i IN 0..3 LOOP
    SELECT rp.user_id INTO v_uid FROM public.okey_room_players rp
    WHERE rp.room_id = v_room.id AND rp.seat_no = v_i;
    v_seat_of[v_i + 1] := v_uid;
  END LOOP;

  v_before := ARRAY[]::bigint[];
  FOR v_i IN 1..4 LOOP
    SELECT points INTO v_pts FROM public.okey_wallets WHERE user_id = v_seat_of[v_i];
    v_before := v_before || v_pts;
  END LOOP;

  PERFORM public.okey_internal_collect_entry_fees(v_room.id);

  FOR v_i IN 1..4 LOOP
    SELECT points INTO v_pts FROM public.okey_wallets WHERE user_id = v_seat_of[v_i];
    IF v_before[v_i] - v_pts <> 100 THEN
      RAISE EXCEPTION 'TEST_FAIL[3]: koltuk % giris ucreti tahsil edilmedi', v_i - 1;
    END IF;
  END LOOP;
  RAISE NOTICE 'TEST_OK[3]: 4 oyuncudan 100er tahsil edildi (brut pot 400)';

  ----------------------------------------------------------------------------
  -- [4] Maç bitince kazanan NET potu alır, komisyon sisteme yazılır
  ----------------------------------------------------------------------------
  v_before := ARRAY[]::bigint[];
  FOR v_i IN 1..4 LOOP
    SELECT points INTO v_pts FROM public.okey_wallets WHERE user_id = v_seat_of[v_i];
    v_before := v_before || v_pts;
  END LOOP;

  -- Koltuk 1 en dusuk ceza ile kazansin
  v_scores := jsonb_build_object('0', 150, '1', -101, '2', 200, '3', 180);
  PERFORM public.okey_internal_award_match(v_room.id, v_scores);

  v_after := ARRAY[]::bigint[];
  FOR v_i IN 1..4 LOOP
    SELECT points INTO v_pts FROM public.okey_wallets WHERE user_id = v_seat_of[v_i];
    v_after := v_after || v_pts;
  END LOOP;

  IF v_after[2] - v_before[2] <> 360 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: kazanan net potu (360) almadi (fark=%)',
      v_after[2] - v_before[2];
  END IF;
  FOR v_i IN 1..4 LOOP
    IF v_i <> 2 AND v_after[v_i] <> v_before[v_i] THEN
      RAISE EXCEPTION 'TEST_FAIL[4]: kaybeden koltuk % puan aldi', v_i - 1;
    END IF;
  END LOOP;

  SELECT COALESCE(sum(amount), 0) INTO v_rev_comm
  FROM public.okey_house_revenue
  WHERE source = 'commission' AND room_id = v_room.id;
  IF v_rev_comm <> 40 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: komisyon 40 olmali, oldu=%', v_rev_comm;
  END IF;
  RAISE NOTICE 'TEST_OK[4]: kazanan 360 aldi, komisyon 40 sisteme yazildi';

  ----------------------------------------------------------------------------
  -- [5] Bu odadan toplam sistem kazanci = oda ucreti + komisyon
  ----------------------------------------------------------------------------
  SELECT COALESCE(sum(amount), 0) INTO v_rev
  FROM public.okey_house_revenue WHERE room_id = v_room.id;
  IF v_rev <> 90 THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: toplam sistem kazanci 90 olmali, oldu=%', v_rev;
  END IF;
  RAISE NOTICE 'TEST_OK[5]: sistem kazanci = 50 (oda) + 40 (komisyon) = 90';

  ----------------------------------------------------------------------------
  -- [6] Oda ucreti 0 iken ACILISTA puan dusmez (giris ucreti el basinda alinir)
  ----------------------------------------------------------------------------
  UPDATE public.okey_settings SET room_creation_fee = 0 WHERE id = true;
  PERFORM set_config('request.jwt.claim.sub', v_users[1]::text, true);
  SELECT points INTO v_creator_before FROM public.okey_wallets WHERE user_id = v_users[1];
  SELECT * INTO v_room FROM public.create_okey_room(false,'katlamasiz','essiz','yardimli',3,100);
  SELECT points INTO v_creator_after FROM public.okey_wallets WHERE user_id = v_users[1];
  IF v_creator_after <> v_creator_before THEN
    RAISE EXCEPTION
      'TEST_FAIL[6]: oda ucreti 0 iken ACILISTA puan dusuldu (giris ucreti el basinda alinir)';
  END IF;
  RAISE NOTICE 'TEST_OK[6]: oda ucreti 0 iken acilista puan dusmuyor';

  ----------------------------------------------------------------------------
  -- [7] Admin oranlari degistirebilir, gecersiz oran reddedilir
  ----------------------------------------------------------------------------
  IF public.is_admin() THEN
    SELECT * INTO v_row FROM public.admin_okey_update_settings(101, 20, 75, 15);
    IF v_row.commission_percent <> 15 OR v_row.room_creation_fee <> 75 THEN
      RAISE EXCEPTION 'TEST_FAIL[7]: admin ayarlari kaydetmedi';
    END IF;
    BEGIN
      PERFORM public.admin_okey_update_settings(101, 20, 75, 99);
      RAISE EXCEPTION 'TEST_FAIL[7]: %%99 komisyon kabul edildi!';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE 'APP:invalid_commission%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'TEST_OK[7]: admin oran degistirebiliyor, gecersiz oran reddediliyor';
  ELSE
    RAISE NOTICE 'TEST_SKIP[7]: calistiran kullanici admin degil';
  END IF;

  RAISE NOTICE '=== SISTEM KAZANCI TESTLERI GECTI ===';
END $$;

ROLLBACK;

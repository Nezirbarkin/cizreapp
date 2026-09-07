-- =============================================================================
-- 101 Okey Plus — KAZANAN BELİRLEME: TEKLİ (eşsiz) ve EŞLİ (2v2) modlar
--   supabase db query --linked --file supabase/tests/manual/okey_payout_modes_test.sql
--
-- TARİHÇE — bu dosya gerçek bir hatayı yakaladı ve iki kez yön değiştirdi:
--   1) Başta POT DAĞITIMINI ölçüyordu ve gerçek bir hata buldu: eşli modda
--      pot tek oyuncuya gidiyor, EŞ hiçbir şey almıyordu.
--   2) Bahis bir süre kaldırılınca ölçüm cüzdandan istatistiğe taşındı.
--   3) Masa puanı geri gelince (ve zorunlu olunca) pot dağıtımı da geri geldi.
--   Bu yüzden test şimdi HEM potu HEM kazanan belirlemeyi ölçüyor.
--
-- Doğrulanan davranış:
--   Eşsiz : cezası en düşük TEK oyuncu potun tamamını alır
--   Eşli  : kazanan takımın İKİ üyesi potu EŞİT paylaşır  <-- eski hata burada
--   Her iki modda kazanan(lar) istatistiğe yazılır
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_users uuid[];
  v_room public.okey_rooms%ROWTYPE;
  v_before bigint[]; v_after bigint[];
  v_seat_of uuid[];  -- koltuk -> user
  v_won_before int[]; v_won_after int[];
  v_i int;
  v_scores jsonb;
  v_uid uuid;
  v_pts bigint;
  v_w int;
BEGIN
  SELECT array_agg(id) INTO v_users FROM (
    SELECT id FROM public.profiles ORDER BY created_at ASC LIMIT 4
  ) t;
  IF array_length(v_users, 1) < 4 THEN
    RAISE EXCEPTION 'TEST_SKIP: 4 kullanici gerekli';
  END IF;

  -- Oda kurma ücreti bu testin ölçtüğü şeyi bulandırmasın
  UPDATE public.okey_settings
  SET commission_percent = 0, room_creation_fee = 0 WHERE id = true;

  FOR v_i IN 1..4 LOOP
    PERFORM public.okey_internal_add_points(
      v_users[v_i], 10000, 'admin_grant',
      'test:' || v_users[v_i]::text || ':' || gen_random_uuid()::text
    );
  END LOOP;

  ----------------------------------------------------------------------------
  -- [1] EŞSİZ: cezası en düşük tek oyuncu kazanan sayılır, PUAN DEĞİŞMEZ
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_users[1]::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(false, 'katlamasiz', 'essiz', 'yardimli', 3, 100);
  FOR v_i IN 2..4 LOOP
    PERFORM set_config('request.jwt.claim.sub', v_users[v_i]::text, true);
    PERFORM public.join_okey_room(v_room.id, NULL);
  END LOOP;

  v_seat_of := ARRAY[NULL, NULL, NULL, NULL]::uuid[];
  FOR v_i IN 0..3 LOOP
    SELECT rp.user_id INTO v_uid FROM public.okey_room_players rp
    WHERE rp.room_id = v_room.id AND rp.seat_no = v_i;
    v_seat_of[v_i + 1] := v_uid;
  END LOOP;

  -- Pot oluşsun diye giriş ücretleri tahsil edilir
  PERFORM public.okey_internal_collect_entry_fees(v_room.id);

  v_before := ARRAY[]::bigint[];
  v_won_before := ARRAY[]::int[];
  FOR v_i IN 1..4 LOOP
    SELECT points INTO v_pts FROM public.okey_wallets WHERE user_id = v_seat_of[v_i];
    v_before := v_before || v_pts;
    SELECT COALESCE(matches_won, 0) INTO v_w
    FROM public.okey_stats WHERE user_id = v_seat_of[v_i];
    v_won_before := v_won_before || COALESCE(v_w, 0);
  END LOOP;

  -- Koltuk 1 en dusuk ceza ile kazansin
  v_scores := jsonb_build_object('0', 150, '1', -101, '2', 200, '3', 180);
  PERFORM public.okey_internal_award_match(v_room.id, v_scores);

  v_after := ARRAY[]::bigint[];
  v_won_after := ARRAY[]::int[];
  FOR v_i IN 1..4 LOOP
    SELECT points INTO v_pts FROM public.okey_wallets WHERE user_id = v_seat_of[v_i];
    v_after := v_after || v_pts;
    SELECT COALESCE(matches_won, 0) INTO v_w
    FROM public.okey_stats WHERE user_id = v_seat_of[v_i];
    v_won_after := v_won_after || COALESCE(v_w, 0);
  END LOOP;

  -- Komisyon %0 olduğu için kazanan brüt potun tamamını alır: 100 x 4 = 400
  IF v_after[2] - v_before[2] <> 400 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: essizde kazanan potun tamamini almadi (fark=%)',
      v_after[2] - v_before[2];
  END IF;
  FOR v_i IN 1..4 LOOP
    IF v_i <> 2 AND v_after[v_i] <> v_before[v_i] THEN
      RAISE EXCEPTION 'TEST_FAIL[1]: kaybeden koltuk % puan aldi', v_i - 1;
    END IF;
  END LOOP;

  -- Koltuk 1 (dizide index 2) kazanan sayilmali
  IF v_won_after[2] <> v_won_before[2] + 1 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: essizde kazanan istatistige yazilmadi';
  END IF;
  FOR v_i IN 1..4 LOOP
    IF v_i <> 2 AND v_won_after[v_i] <> v_won_before[v_i] THEN
      RAISE EXCEPTION 'TEST_FAIL[1]: kaybeden koltuk % kazanan sayildi', v_i - 1;
    END IF;
  END LOOP;
  RAISE NOTICE 'TEST_OK[1]: ESSIZ — kazanan potun tamamini aldi (400)';

  ----------------------------------------------------------------------------
  -- [2] EŞLİ (2v2): kazanan takimin İKİ üyesi de kazanan sayilir
  --     (Eski pot hatasinin ciktigi yer tam olarak burasiydi.)
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_users[1]::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(false, 'katlamasiz', 'esli', 'yardimli', 3, 100);
  FOR v_i IN 2..4 LOOP
    PERFORM set_config('request.jwt.claim.sub', v_users[v_i]::text, true);
    PERFORM public.join_okey_room(v_room.id, NULL);
  END LOOP;

  v_seat_of := ARRAY[NULL, NULL, NULL, NULL]::uuid[];
  FOR v_i IN 0..3 LOOP
    SELECT rp.user_id INTO v_uid FROM public.okey_room_players rp
    WHERE rp.room_id = v_room.id AND rp.seat_no = v_i;
    v_seat_of[v_i + 1] := v_uid;
  END LOOP;

  -- Pot oluşsun diye giriş ücretleri tahsil edilir
  PERFORM public.okey_internal_collect_entry_fees(v_room.id);

  v_before := ARRAY[]::bigint[];
  v_won_before := ARRAY[]::int[];
  FOR v_i IN 1..4 LOOP
    SELECT points INTO v_pts FROM public.okey_wallets WHERE user_id = v_seat_of[v_i];
    v_before := v_before || v_pts;
    SELECT COALESCE(matches_won, 0) INTO v_w
    FROM public.okey_stats WHERE user_id = v_seat_of[v_i];
    v_won_before := v_won_before || COALESCE(v_w, 0);
  END LOOP;

  -- Takim A (0+2) = 10 + 20 = 30 ; Takim B (1+3) = 200 + 180 = 380 -> A kazanir
  v_scores := jsonb_build_object('0', 10, '1', 200, '2', 20, '3', 180);
  PERFORM public.okey_internal_award_match(v_room.id, v_scores);

  v_after := ARRAY[]::bigint[];
  v_won_after := ARRAY[]::int[];
  FOR v_i IN 1..4 LOOP
    SELECT points INTO v_pts FROM public.okey_wallets WHERE user_id = v_seat_of[v_i];
    v_after := v_after || v_pts;
    SELECT COALESCE(matches_won, 0) INTO v_w
    FROM public.okey_stats WHERE user_id = v_seat_of[v_i];
    v_won_after := v_won_after || COALESCE(v_w, 0);
  END LOOP;

  -- EŞLİ: pot kazanan takımın İKİ üyesi arasında EŞİT paylaşılır (200 + 200)
  IF v_after[1] - v_before[1] <> 200 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: koltuk 0 payini (200) almadi (fark=%)',
      v_after[1] - v_before[1];
  END IF;
  IF v_after[3] - v_before[3] <> 200 THEN
    RAISE EXCEPTION
      'TEST_FAIL[2]: ES (koltuk 2) payini (200) almadi (fark=%) — esli mod hatasi!',
      v_after[3] - v_before[3];
  END IF;
  IF v_after[2] <> v_before[2] OR v_after[4] <> v_before[4] THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: kaybeden takim puan aldi';
  END IF;

  -- Koltuk 0 (index 1) VE koltuk 2 (index 3) kazanan sayilmali
  IF v_won_after[1] <> v_won_before[1] + 1 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: koltuk 0 kazanan sayilmadi';
  END IF;
  IF v_won_after[3] <> v_won_before[3] + 1 THEN
    RAISE EXCEPTION
      'TEST_FAIL[2]: ES (koltuk 2) kazanan sayilmadi — esli mod hatasi!';
  END IF;
  IF v_won_after[2] <> v_won_before[2] OR v_won_after[4] <> v_won_before[4] THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: kaybeden takim kazanan sayildi';
  END IF;
  RAISE NOTICE 'TEST_OK[2]: ESLI — kazanan takimin IKI uyesi de 200er aldi';

  ----------------------------------------------------------------------------
  -- [3] Masa puanı ZORUNLU: ücretsiz masa açılamaz
  ----------------------------------------------------------------------------
  IF v_room.entry_fee <> 100 THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: masa puani kaydedilmedi (%)', v_room.entry_fee;
  END IF;

  DECLARE
    v_blocked3 boolean := false;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_users[1]::text, true);
    BEGIN
      PERFORM public.create_okey_room(
        false, 'katlamasiz', 'essiz', 'yardimli', 3, 0);
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'APP:entry_fee_too_low%' THEN
        v_blocked3 := true;
      ELSE
        RAISE;
      END IF;
    END;
    IF NOT v_blocked3 THEN
      RAISE EXCEPTION 'TEST_FAIL[3]: ucretsiz masa acildi!';
    END IF;
  END;
  RAISE NOTICE 'TEST_OK[3]: masa puani zorunlu, ucretsiz masa acilamiyor';

  RAISE NOTICE '=== KAZANAN BELIRLEME TESTLERI GECTI ===';
END $$;

ROLLBACK;

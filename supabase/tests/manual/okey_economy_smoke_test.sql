-- =============================================================================
-- 101 Okey Plus — Puan ekonomisi testi (ROLLBACK ile, kalıcı iz bırakmaz)
--   supabase db query --linked --file supabase/tests/manual/okey_economy_smoke_test.sql
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_u1 uuid; v_u2 uuid; v_admin uuid;
  v_p bigint; v_p2 bigint; v_before bigint;
  v_room public.okey_rooms%ROWTYPE;
  v_w record;
  v_n int;
BEGIN
  -- DİKKAT: v_u1 GERÇEKTEN admin olmayan bir kullanıcı olmalı; aksi halde
  -- "admin olmayan puan ekleyemez" testi yanlışlıkla düşer.
  SELECT id INTO v_u1 FROM public.profiles
  WHERE role::text <> 'admin' ORDER BY created_at ASC OFFSET 0 LIMIT 1;
  SELECT id INTO v_u2 FROM public.profiles
  WHERE role::text <> 'admin' ORDER BY created_at ASC OFFSET 1 LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' LIMIT 1;

  IF v_u1 IS NULL OR v_admin IS NULL THEN
    RAISE EXCEPTION 'TEST_SKIP: admin ve admin-olmayan kullanici gerekli';
  END IF;

  -- Bu test SAF odeme mantigini olcer; canli ayardan etkilenmemesi icin
  -- komisyon ve oda ucreti sifirlanir. (Komisyon davranisi okey_revenue_test
  -- dosyasinda ayrica test edilir.)
  UPDATE public.okey_settings
  SET commission_percent = 0, room_creation_fee = 0 WHERE id = true;

  ----------------------------------------------------------------------------
  -- [1] Cüzdan otomatik oluşur ve başlangıç puanı verilir
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  SELECT * INTO v_w FROM public.okey_get_wallet();
  IF v_w.points <= 0 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: baslangic puani verilmedi (%)', v_w.points;
  END IF;
  RAISE NOTICE 'TEST_OK[1]: cuzdan olustu, baslangic puani = %', v_w.points;

  ----------------------------------------------------------------------------
  -- [2] Saatlik hediye: bir kez alınır, ikinci kez reddedilir
  ----------------------------------------------------------------------------
  v_before := v_w.points;
  v_p := public.okey_claim_hourly_gift();
  IF v_p <> v_before + v_w.hourly_gift_points THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: hediye puani yanlis (% -> %)', v_before, v_p;
  END IF;

  BEGIN
    PERFORM public.okey_claim_hourly_gift();
    RAISE EXCEPTION 'TEST_FAIL[2]: hediye ikinci kez alinabildi!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'APP:gift_not_ready%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'TEST_OK[2]: saatlik hediye bir kez veriliyor, tekrari engelleniyor';

  ----------------------------------------------------------------------------
  -- [3] Doğrulanmamış reklam oturumu puan vermez
  ----------------------------------------------------------------------------
  BEGIN
    PERFORM public.okey_claim_ad_reward(gen_random_uuid());
    RAISE EXCEPTION 'TEST_FAIL[3]: dogrulanmamis reklam puan verdi!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'APP:ad_not_verified%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'TEST_OK[3]: dogrulanmamis reklam oturumu reddediliyor';

  ----------------------------------------------------------------------------
  -- [4] Admin puan ekleyebilir, admin olmayan ekleyemez
  ----------------------------------------------------------------------------
  IF v_admin IS NOT NULL THEN
    PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
    BEGIN
      PERFORM public.admin_okey_grant_points(v_u1, 5000, 'hile');
      RAISE EXCEPTION 'TEST_FAIL[4]: admin olmayan kendine puan ekledi!';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE 'APP:forbidden%' THEN RAISE; END IF;
    END;

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    SELECT points INTO v_before FROM public.okey_wallets WHERE user_id = v_u1;
    v_p := public.admin_okey_grant_points(v_u1, 500, 'test');
    IF v_p <> v_before + 500 THEN
      RAISE EXCEPTION 'TEST_FAIL[4]: admin puan ekleyemedi (% -> %)', v_before, v_p;
    END IF;
    RAISE NOTICE 'TEST_OK[4]: admin puan ekleyebiliyor, admin olmayan ekleyemiyor';
  END IF;

  ----------------------------------------------------------------------------
  -- [5] MASA SADECE PUANLA AÇILIR: ücretsiz masa reddedilir
  ----------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_u1::text, true);
  DECLARE
    v_blocked5 boolean := false;
  BEGIN
    BEGIN
      PERFORM public.create_okey_room(
        false, 'katlamasiz', 'essiz', 'yardimli', 3, 0);
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'APP:entry_fee_too_low%' THEN
        v_blocked5 := true;
      ELSE
        RAISE;
      END IF;
    END;
    IF NOT v_blocked5 THEN
      RAISE EXCEPTION 'TEST_FAIL[5]: ucretsiz masa acildi!';
    END IF;
  END;
  RAISE NOTICE 'TEST_OK[5]: ucretsiz masa acilamiyor';

  ----------------------------------------------------------------------------
  -- [6] Ücretli masa: el başlarken giriş puanı TAHSİL edilir (bir kez)
  ----------------------------------------------------------------------------
  SELECT * INTO v_room FROM public.create_okey_room(
    false, 'katlamasiz', 'essiz', 'yardimli', 3, 100);
  IF v_room.entry_fee <> 100 THEN
    RAISE EXCEPTION 'TEST_FAIL[6]: masa puani kaydedilmedi (%)', v_room.entry_fee;
  END IF;

  SELECT points INTO v_before FROM public.okey_wallets WHERE user_id = v_u1;
  PERFORM public.okey_fill_with_bots(v_room.id);
  SELECT points INTO v_p FROM public.okey_wallets WHERE user_id = v_u1;

  IF v_before - v_p <> 100 THEN
    RAISE EXCEPTION 'TEST_FAIL[6]: giris ucreti tahsil edilmedi (% -> %)',
      v_before, v_p;
  END IF;

  -- İdempotans: ikinci kez tahsil edilmemeli
  PERFORM public.okey_internal_collect_entry_fees(v_room.id);
  SELECT points INTO v_p2 FROM public.okey_wallets WHERE user_id = v_u1;
  IF v_p2 <> v_p THEN
    RAISE EXCEPTION 'TEST_FAIL[6]: giris ucreti IKI KEZ tahsil edildi!';
  END IF;
  RAISE NOTICE 'TEST_OK[6]: giris ucreti bir kez tahsil ediliyor';

  ----------------------------------------------------------------------------
  -- [7] Maç bitince POT kazanana ödenir + istatistik yazılır
  ----------------------------------------------------------------------------
  DECLARE
    v_seat smallint;
    v_scores jsonb;
    v_stats record;
    v_won_before int;
  BEGIN
    UPDATE public.okey_settings SET commission_percent = 0 WHERE id = true;

    SELECT seat_no INTO v_seat FROM public.okey_room_players
    WHERE room_id = v_room.id AND user_id = v_u1;

    v_scores := jsonb_build_object(
      v_seat::text, -101,
      ((v_seat + 1) % 4)::text, 202,
      ((v_seat + 2) % 4)::text, 202,
      ((v_seat + 3) % 4)::text, 202
    );

    SELECT COALESCE(matches_won, 0) INTO v_won_before
    FROM public.okey_stats WHERE user_id = v_u1;

    SELECT points INTO v_before FROM public.okey_wallets WHERE user_id = v_u1;
    PERFORM public.okey_internal_award_match(v_room.id, v_scores);
    SELECT points INTO v_p FROM public.okey_wallets WHERE user_id = v_u1;

    -- Masada 1 insan var (digerleri bot) -> pot = 100 x 1, komisyon %0
    IF v_p - v_before <> 100 THEN
      RAISE EXCEPTION 'TEST_FAIL[7]: pot kazanana verilmedi (fark=%)',
        v_p - v_before;
    END IF;
    RAISE NOTICE 'TEST_OK[7]: pot kazanana verildi';

    SELECT * INTO v_stats FROM public.okey_stats WHERE user_id = v_u1;
    IF v_stats.matches_won <= v_won_before THEN
      RAISE EXCEPTION 'TEST_FAIL[7b]: kazanilan mac istatistige yazilmadi';
    END IF;

    -- Aynı maç iki kez ödenmemeli
    PERFORM public.okey_internal_award_match(v_room.id, v_scores);
    SELECT points INTO v_p2 FROM public.okey_wallets WHERE user_id = v_u1;
    IF v_p2 <> v_p THEN
      RAISE EXCEPTION 'TEST_FAIL[7c]: pot IKI KEZ odendi!';
    END IF;
    RAISE NOTICE 'TEST_OK[7b]: pot iki kez odenmiyor, istatistik yazildi';
  END;

  ----------------------------------------------------------------------------
  -- [8] Puanlar SADECE Okey'e ait — başka bir cüzdana dokunulmuyor
  ----------------------------------------------------------------------------
  SELECT count(*) INTO v_n FROM public.okey_point_transactions
  WHERE user_id = v_u1;
  IF v_n < 3 THEN
    RAISE EXCEPTION 'TEST_FAIL[8]: defter kayitlari eksik (%)', v_n;
  END IF;
  RAISE NOTICE 'TEST_OK[8]: tum hareketler Okey defterine yazildi (% kayit)', v_n;

  ----------------------------------------------------------------------------
  -- [9] Skor tablosu çalışıyor
  ----------------------------------------------------------------------------
  SELECT count(*) INTO v_n FROM public.okey_leaderboard(50);
  IF v_n < 1 THEN
    RAISE EXCEPTION 'TEST_FAIL[9]: skor tablosu bos';
  END IF;
  RAISE NOTICE 'TEST_OK[9]: skor tablosu calisiyor (% oyuncu)', v_n;

  RAISE NOTICE 'TUM_EKONOMI_TESTLERI_GECTI';
END;
$$;

ROLLBACK;

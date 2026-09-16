-- =============================================================================
-- 101 Okey — BOT KOLTUKLARI DA POTA KATILIR (kullanıcı bildirimi 2026-09-08:
-- "okey 101 oyunda kazanan kişiye sadece masa ücreti iade ediliyor,
--  çip kazanmıyor")
-- -----------------------------------------------------------------------------
-- ## Ölçülen sorun
--
-- Pot YALNIZCA insan koltuklarından toplanıyordu:
--
--     kaybedenler_potu = masa_puanı × (insan_sayısı − kazanan_insan_sayısı)
--
-- Bot koltuğunun cüzdanı yok (bkz. 20260908180001: botlar bilerek ekonominin
-- DIŞINDA tutuldu), dolayısıyla masaya hiçbir şey koymuyordu. Üç botla
-- oynanan bir masada insan sayısı 1, kazanan insan sayısı 1 → pot SIFIR.
-- Kazanan yalnızca kendi masa puanının iadesini (stake_refund) alıyor,
-- match_win satırı hiç yazılmıyordu. Oyuncu maçı kazanıyor, cüzdanı kuruşu
-- kuruşuna aynı kalıyordu.
--
-- Bu, masaların ÇOĞUNLUĞUNU kapsıyor: hızlı eşleştirme (20260907000004) ve
-- otomatik doldurma (20260908180001) ücretli masayı botlarla dolduruyor.
-- Yani ödüllü tek oyun türü, dört gerçek insanın aynı anda oturduğu masaydı.
--
-- ## Yeni kural
--
-- KAYBEDEN BOT KOLTUĞU DA MASA PUANI KOYAR; parayı kasa fonlar:
--
--     bot_payı         = masa_puanı × bot_stake_percent / 100
--     kaybedenler_potu = masa_puanı × kaybeden_insan_sayısı
--                      + bot_payı  × kaybeden_bot_sayısı
--
-- bot_stake_percent yeni bir admin ayarıdır (varsayılan 100 = bot tıpkı bir
-- insan gibi masaya girer). 0 yazılırsa davranış bu göçten önceki haline
-- döner; enflasyon panelden kısılabilir olsun diye ayar olarak eklendi,
-- sabit olarak gömülmedi.
--
-- NEDEN KAZANAN BOTUN PAYI BASILMIYOR: bot koltuğu potu kazandıysa (masada
-- insan kazanan yoksa) hiç puan ÜRETİLMEZ. Aksi halde kasa, hemen ardından
-- unclaimed_pot olarak geri aldığı bir tutarı basmış olurdu — defter aynı
-- yere gelirdi ama raporlarda olmayan bir para akışı görünürdü.
--
-- NEDEN KOMİSYON BOT PAYINDAN DA KESİLİYOR: commission_percent bu oyunun tek
-- enflasyon frenidir. Kasanın fonladığı tutar frenden muaf tutulsaydı, bot
-- masalarında dolaşıma giren çip hiçbir yerde geri emilmezdi.
--
-- ## Defter
--
-- Kasanın fonladığı tutar okey_house_revenue'ya EKSİ işaretli bir 'bot_stake'
-- satırı olarak yazılır. Böylece "Toplam Kazanç" gerçekten NET olur: basılan
-- çip, tahsil edilen komisyon ve oda ücretiyle aynı defterde karşılaşır.
-- Bunun için tablonun amount > 0 kısıtı amount <> 0 yapıldı — kasa bu oyunda
-- ilk kez para ÖDÜYOR, o yüzden eski kısıt artık gerçeği anlatmıyordu.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) AYAR: bot koltuğunun masaya koyduğu payın yüzdesi
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS bot_stake_percent int NOT NULL DEFAULT 100;

ALTER TABLE public.okey_settings
  DROP CONSTRAINT IF EXISTS okey_settings_bot_stake_percent_check;
ALTER TABLE public.okey_settings
  ADD CONSTRAINT okey_settings_bot_stake_percent_check
  CHECK (bot_stake_percent >= 0 AND bot_stake_percent <= 100);

COMMENT ON COLUMN public.okey_settings.bot_stake_percent IS
  'Kaybeden BOT koltuğunun pota koyduğu masa puanı yüzdesi (0-100). Kasa fonlar; 100 = bot tıpkı bir insan gibi masaya girer, 0 = botlar pota hiç katılmaz.';

-- -----------------------------------------------------------------------------
-- 2) DEFTER: kasa artık ödeme de yapabiliyor
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_house_revenue
  DROP CONSTRAINT IF EXISTS okey_house_revenue_amount_check;
ALTER TABLE public.okey_house_revenue
  ADD CONSTRAINT okey_house_revenue_amount_check CHECK (amount <> 0);

ALTER TABLE public.okey_house_revenue
  DROP CONSTRAINT IF EXISTS okey_house_revenue_source_check;
ALTER TABLE public.okey_house_revenue
  ADD CONSTRAINT okey_house_revenue_source_check
  CHECK (source IN ('room_fee', 'commission', 'unclaimed_pot', 'gift', 'bot_stake'));

-- -----------------------------------------------------------------------------
-- 3) okey_internal_award_match — gövde 20260905000004'ten taşındı.
--    TEK fark: kaybeden bot koltukları da pota katkı yapar.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.okey_internal_award_match(
  p_room_id uuid,
  p_final_scores jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_room public.okey_rooms%ROWTYPE;
  v_seat int;
  v_score int;
  v_best int;
  v_player record;
  v_winner_seats int[] := ARRAY[]::int[];
  v_winner_users uuid[] := ARRAY[]::uuid[];
  v_team_a int;
  v_team_b int;
  v_human_count int;
  v_winner_human_count int;
  v_bot_loser_count int := 0;
  v_bot_ante bigint := 0;
  v_bot_pot bigint := 0;
  v_loser_pot bigint := 0;
  v_commission bigint := 0;
  v_pot_net bigint := 0;
  v_percent int;
  v_bot_percent int;
  v_share bigint;
  v_remainder bigint;
  v_uid uuid;
  v_i int;
BEGIN
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id;
  IF v_room.id IS NULL THEN RETURN; END IF;

  -- KAZANAN(LAR) — beraberlikte HEPSİ kazanır, pot aralarında paylaşılır.
  IF v_room.team_mode = 'esli' THEN
    v_team_a := COALESCE((p_final_scores ->> '0')::int, 0)
              + COALESCE((p_final_scores ->> '2')::int, 0);
    v_team_b := COALESCE((p_final_scores ->> '1')::int, 0)
              + COALESCE((p_final_scores ->> '3')::int, 0);
    IF v_team_a = v_team_b THEN
      v_winner_seats := ARRAY[0, 1, 2, 3]; -- berabere: giriş ücreti iadesi
    ELSIF v_team_a < v_team_b THEN
      v_winner_seats := ARRAY[0, 2];
    ELSE
      v_winner_seats := ARRAY[1, 3];
    END IF;
  ELSE
    v_best := NULL;
    FOR v_seat IN 0..3 LOOP
      v_score := COALESCE((p_final_scores ->> v_seat::text)::int, 0);
      IF v_best IS NULL OR v_score < v_best THEN
        v_best := v_score;
      END IF;
    END LOOP;
    FOR v_seat IN 0..3 LOOP
      IF COALESCE((p_final_scores ->> v_seat::text)::int, 0) = v_best THEN
        v_winner_seats := v_winner_seats || v_seat;
      END IF;
    END LOOP;
  END IF;

  FOREACH v_seat IN ARRAY v_winner_seats LOOP
    SELECT rp.user_id INTO v_uid FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.seat_no = v_seat;
    IF v_uid IS NOT NULL THEN
      v_winner_users := v_winner_users || v_uid;
    END IF;
  END LOOP;

  -- POT (yalnızca ÜCRETLİ masada ve giriş tahsil edilmişse)
  IF v_room.table_stake > 0 AND v_room.entry_fee_collected THEN
    SELECT count(*)::int INTO v_human_count FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL;

    v_winner_human_count := COALESCE(array_length(v_winner_users, 1), 0);

    -- 1) MASA PUANI İADESİ — kazanandan masa ücreti alınmaz.
    --    Komisyondan ÖNCE ve komisyondan BAĞIMSIZ: bu para hiç dolaşıma
    --    çıkmadı, sadece oyuncunun cebine geri kondu.
    FOR v_i IN 1 .. v_winner_human_count LOOP
      PERFORM public.okey_internal_add_points(
        v_winner_users[v_i],
        v_room.table_stake::bigint,
        'stake_refund',
        p_room_id::text || ':' || v_winner_users[v_i]::text
      );
    END LOOP;

    -- 2) KAYBEDEN BOT KOLTUKLARI — masaya kasa adına girerler.
    --    BOŞ koltuk sayılmaz: is_bot = false AND user_id IS NULL satırları
    --    oyuncu bekleyen boş sandalyelerdir (bkz. okey_fill_with_bots) ve
    --    oynamayan bir sandalye pota para koymamalı.
    IF v_winner_human_count > 0 THEN
      SELECT count(*)::int INTO v_bot_loser_count
      FROM public.okey_room_players AS rp
      WHERE rp.room_id = p_room_id
        AND rp.is_bot
        AND rp.user_id IS NULL
        AND NOT (rp.seat_no = ANY(v_winner_seats));

      SELECT COALESCE(s.bot_stake_percent, 100) INTO v_bot_percent
      FROM public.okey_settings AS s WHERE s.id = true;

      v_bot_ante := (v_room.table_stake::bigint
                     * COALESCE(v_bot_percent, 100)) / 100;
      v_bot_pot := v_bot_ante * COALESCE(v_bot_loser_count, 0);
    END IF;

    -- 3) KAYBEDENLERİN POTU — komisyon YALNIZCA buradan kesilir.
    v_loser_pot := v_room.table_stake::bigint
                 * GREATEST(COALESCE(v_human_count, 0) - v_winner_human_count, 0)
                 + v_bot_pot;

    SELECT COALESCE(s.commission_percent, 0) INTO v_percent
    FROM public.okey_settings AS s WHERE s.id = true;

    v_commission := (v_loser_pot * COALESCE(v_percent, 0)) / 100;
    v_pot_net := v_loser_pot - v_commission;

    -- Kasanın FONLADIĞI tutar eksi işaretle yazılır: "Toplam Kazanç" böylece
    -- basılan çipi de görür ve gerçekten net kalır.
    IF v_bot_pot > 0 THEN
      INSERT INTO public.okey_house_revenue (source, amount, room_id, ref)
      VALUES ('bot_stake', -v_bot_pot, p_room_id, p_room_id::text)
      ON CONFLICT DO NOTHING;
    END IF;

    IF v_commission > 0 THEN
      INSERT INTO public.okey_house_revenue (source, amount, room_id, ref)
      VALUES ('commission', v_commission, p_room_id, p_room_id::text)
      ON CONFLICT DO NOTHING;
    END IF;

    IF v_winner_human_count > 0 AND v_pot_net > 0 THEN
      v_share := v_pot_net / v_winner_human_count;
      v_remainder := v_pot_net - (v_share * v_winner_human_count);

      FOR v_i IN 1 .. v_winner_human_count LOOP
        PERFORM public.okey_internal_add_points(
          v_winner_users[v_i],
          v_share + CASE WHEN v_i = 1 THEN v_remainder ELSE 0 END,
          'match_win',
          p_room_id::text || ':' || v_winner_users[v_i]::text
        );
      END LOOP;
    ELSIF v_pot_net > 0 THEN
      -- Kazananların tamamı BOT: pot kimseye gitmiyor. Yok saymak yerine
      -- deftere yazılır ki dolaşımdan çıkan puan raporlarda görünsün.
      -- (v_bot_pot bu dalda zaten 0'dır: kasa dağıtılmayacak bir pota hiç
      --  para koymaz.)
      INSERT INTO public.okey_house_revenue (source, amount, room_id, ref)
      VALUES ('unclaimed_pot', v_pot_net, p_room_id, p_room_id::text)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- İSTATİSTİKLER / SKOR TABLOSU
  FOR v_player IN
    SELECT rp.user_id, rp.seat_no FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL
  LOOP
    v_score := COALESCE((p_final_scores ->> v_player.seat_no::text)::int, 0);

    INSERT INTO public.okey_stats AS st (
      user_id, matches_played, matches_won, total_points_won, best_match_score
    ) VALUES (
      v_player.user_id, 1,
      CASE WHEN v_player.seat_no = ANY(v_winner_seats) THEN 1 ELSE 0 END,
      CASE WHEN v_player.seat_no = ANY(v_winner_seats)
                AND COALESCE(v_winner_human_count, 0) > 0
           THEN v_pot_net / v_winner_human_count ELSE 0 END,
      v_score
    )
    ON CONFLICT (user_id) DO UPDATE SET
      matches_played = st.matches_played + 1,
      matches_won = st.matches_won + EXCLUDED.matches_won,
      total_points_won = st.total_points_won + EXCLUDED.total_points_won,
      best_match_score = LEAST(
        COALESCE(st.best_match_score, EXCLUDED.best_match_score),
        EXCLUDED.best_match_score
      ),
      updated_at = now();
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_award_match(uuid, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4) ADMIN AYARI — ayrı RPC (bkz. 20260905000006'daki gerekçe: on bir
--    parametreli admin_okey_update_settings imzasını büyütmek DROP + yeniden
--    GRANT + istemci güncellemesi zinciri demek).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_admin_set_bot_stake_percent(int);

CREATE FUNCTION public.okey_admin_set_bot_stake_percent(p_percent int)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_value int := LEAST(GREATEST(COALESCE(p_percent, 100), 0), 100);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:admin_only' USING ERRCODE = '42501';
  END IF;
  UPDATE public.okey_settings SET bot_stake_percent = v_value WHERE id = true;
  RETURN v_value;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_admin_set_bot_stake_percent(int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_admin_set_bot_stake_percent(int)
  TO authenticated;

DROP FUNCTION IF EXISTS public.okey_admin_get_bot_stake_percent();

CREATE FUNCTION public.okey_admin_get_bot_stake_percent()
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_value int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:admin_only' USING ERRCODE = '42501';
  END IF;
  SELECT COALESCE(s.bot_stake_percent, 100) INTO v_value
  FROM public.okey_settings AS s WHERE s.id = true;
  RETURN COALESCE(v_value, 100);
END;
$$;
REVOKE ALL ON FUNCTION public.okey_admin_get_bot_stake_percent()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_admin_get_bot_stake_percent()
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 5) RAPOR — kasanın bot masalarında bastığı çip ayrı bir kalem olsun.
--
--    'bot_stake' satırları EKSİ olduğu için total_revenue ve today_revenue
--    kendiliğinden netleşir; ayrıca sütun olarak da verilir, yoksa panelde
--    "Toplam Kazanç neden düştü" sorusunun cevabı hiçbir yerde görünmezdi.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_okey_revenue_summary();

CREATE FUNCTION public.admin_okey_revenue_summary()
RETURNS TABLE(
  total_revenue bigint,
  room_fee_total bigint,
  commission_total bigint,
  today_revenue bigint,
  total_points_in_circulation bigint,
  bot_stake_total bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    COALESCE((SELECT sum(amount) FROM public.okey_house_revenue), 0),
    COALESCE((SELECT sum(amount) FROM public.okey_house_revenue WHERE source = 'room_fee'), 0),
    COALESCE((SELECT sum(amount) FROM public.okey_house_revenue WHERE source = 'commission'), 0),
    COALESCE((SELECT sum(amount) FROM public.okey_house_revenue
              WHERE created_at >= date_trunc('day', now())), 0),
    COALESCE((SELECT sum(points) FROM public.okey_wallets), 0),
    COALESCE((SELECT -sum(amount) FROM public.okey_house_revenue WHERE source = 'bot_stake'), 0)
  WHERE public.is_admin();
$$;
REVOKE ALL ON FUNCTION public.admin_okey_revenue_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_revenue_summary() TO authenticated;

COMMENT ON FUNCTION public.admin_okey_revenue_summary() IS
  'Sistem kazancı özeti. total/today NETTİR: bot masalarında kasanın fonladığı pot payı (bot_stake, eksi işaretli) düşülmüştür. bot_stake_total o tutarı ARTI işaretle ayrıca verir.';

NOTIFY pgrst, 'reload schema';

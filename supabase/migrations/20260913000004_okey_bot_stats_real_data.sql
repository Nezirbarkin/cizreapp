-- =============================================================================
-- 101 OKEY — BOTLARIN PROFİLİ GERÇEK VERİYLE (kullanıcı isteği, 2026-09-13:
-- "botlarında gercek verileri göster")
-- -----------------------------------------------------------------------------
-- SORUN: `okey_bot_public_stats` bir bota HİÇ oynamamış gibi davranıyordu —
-- profil id'sinden türeyen sabit bir hash formülüyle (`500 + seed % 9500`
-- puan, `60 + seed % 340` "oynanan maç" vb.) TAMAMEN UYDURMA sayılar
-- üretiyordu. Oysa botlar gerçekten oynuyor: her masada botların koltuğu
-- `okey_room_players`de, oynadıkları her el `okey_matches`te (kazananıyla
-- birlikte, `winner_seat`), her maçın final skoru `okey_matches.scores`te
-- gerçekten kayıtlı duruyor. Bu veri zaten vardı, hiç okunmuyordu.
--
-- ÇÖZÜM: gerçek oyuncularla AYNI şeyi yapan bir istatistik tablosu —
-- `okey_bot_stats` — ve onu besleyen İKİ kanca:
--   * `okey_internal_record_hand_stats` — HER el bittiğinde (bkz.
--     okey_internal_finalize_hand) hands_played/hands_won
--   * `okey_internal_award_match` — HER maç (oda) bittiğinde
--     matches_played/matches_won/best_match_score/total_final_score
-- Gerçek oyuncu tarafındaki iki fonksiyon zaten bu iki kancayı çağırıyordu;
-- burada yalnızca "bot koltuğu da say" dalı EKLENİYOR — insan dalı
-- (`WHERE user_id IS NOT NULL`) hiç değişmiyor.
--
-- GEÇMİŞ VERİ KAYBOLMASIN diye bir SEFERLİK BACKFILL de var: `okey_matches`
-- ve `okey_rooms` zaten geçmişteki her eli ve maçı tutuyor, o yüzden bugüne
-- kadar oynanmış botlu masalar da hesaba katılır — geçiş anında tablo aniden
-- bomboş görünmez.
--
-- PUAN (headline sayı) İÇİN AYRI BİR GEREKÇE GEREKİYOR: botlar ekonominin
-- dışındadır (bkz. 20260908130001) — cüzdanları yoktur, kazandıkları pot
-- asla basılmaz (bkz. 20260908190001 "kazanan botun payı basılmıyor"). Yani
-- gerçek bir oyuncudaki "puan = cüzdan bakiyesi" tanımının bot için birebir
-- karşılığı YOKTUR — kasadan para basmadan böyle bir bakiye üretilemez.
-- Bunun yerine puan, botun GERÇEK maç performansından türetilir:
--
--     puan = 1000 − (o bota ait tüm final skorların ortalaması)
--
-- Okey'de skor bir CEZADIR (düşük = iyi); bu yüzden ortalama final skoru
-- DÜŞÜK olan (sık kazanan) bir bot 1000'in ÜSTÜNE çıkar, YÜKSEK olan
-- 1000'in altına düşer — insan cüzdanındaki "kazanınca artar, kaybedince
-- eksilir" hissini TAMAMEN gerçek maç sonuçlarından üretir. Formüldeki 1000,
-- `okey_settings.starting_points` ile aynı sayıdır (bilinçli: iki tarafın
-- başlangıç noktası aynı olsun).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) TABLO — okey_stats'ın bot karşılığı
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_bot_stats (
  bot_profile_id uuid PRIMARY KEY
    REFERENCES public.okey_bot_profiles (id) ON DELETE CASCADE,
  matches_played int NOT NULL DEFAULT 0,
  matches_won int NOT NULL DEFAULT 0,
  hands_played int NOT NULL DEFAULT 0,
  hands_won int NOT NULL DEFAULT 0,
  -- Final skorların TOPLAMI (puan ortalamasını hesaplamak için). "Kazanılan
  -- puan" değildir — botun asla almadığı bir pot payı burada yoktur.
  total_final_score bigint NOT NULL DEFAULT 0,
  best_match_score int,
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_bot_stats IS
  'okey_stats''ın bot karşılığı: bir bot kimliğinin GERÇEKTEN oynadığı ellerden/maçlardan türeyen istatistikler. okey_stats''ın tersine botun kendi satırı yoktur diye UYDURULMAZ — okey_matches/okey_room_players''dan okunur. Tek okuyucu okey_bot_public_stats.';

ALTER TABLE public.okey_bot_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS okey_bot_stats_select ON public.okey_bot_stats;
CREATE POLICY okey_bot_stats_select ON public.okey_bot_stats
  FOR SELECT USING (true);

-- Yazma yalnızca SECURITY DEFINER fonksiyonlar üzerinden (sahip RLS'i atlar,
-- okey_stats'ın bugünkü deseniyle aynı — bkz. yorum yukarıda).
REVOKE ALL ON public.okey_bot_stats FROM PUBLIC, anon;
GRANT SELECT ON public.okey_bot_stats TO authenticated;

-- -----------------------------------------------------------------------------
-- 2) BACKFILL — bugüne kadar oynanmış botlu eller/maçlar (TEK SEFERLİK)
-- -----------------------------------------------------------------------------
-- Elde ölçüt: `okey_matches.status = 'finished'` olan HER el sayılır (oda
-- sonradan terk edilmiş olsa bile — gerçek oyuncu tarafında da aynı: her
-- biten el `okey_internal_record_hand_stats`i çalıştırır, odanın akıbeti
-- fark etmez).
--
-- Maçta (oda) ölçüt: `okey_rooms.status = 'finished'` olan odalar — ancak
-- böyle bir odada `okey_internal_award_match` gerçekten çalışmıştır. Kazanan
-- koltuk(lar), o odanın SON eldeki (en yüksek hand_no) kümülatif `scores`
-- değerinden `okey_internal_award_match` ile AYNI algoritmayla çıkarılır:
-- eşli modda takım toplamı, eşsizde en düşük skor (berabere = hepsi kazanır).
WITH hand_agg AS (
  SELECT rp.bot_profile_id,
         count(*)::int AS hands_played,
         count(*) FILTER (WHERE m.winner_seat = rp.seat_no)::int AS hands_won
  FROM public.okey_matches AS m
  JOIN public.okey_room_players AS rp
    ON rp.room_id = m.room_id AND rp.bot_profile_id IS NOT NULL
  WHERE m.status = 'finished'
  GROUP BY rp.bot_profile_id
),
last_hand AS (
  SELECT DISTINCT ON (m.room_id) m.room_id, m.scores
  FROM public.okey_matches AS m
  JOIN public.okey_rooms AS r ON r.id = m.room_id
  WHERE r.status = 'finished'
  ORDER BY m.room_id, m.hand_no DESC
),
room_result AS (
  SELECT
    lh.room_id,
    lh.scores,
    CASE WHEN r.team_mode = 'esli' THEN
      CASE
        WHEN (COALESCE((lh.scores ->> '0')::int, 0) + COALESCE((lh.scores ->> '2')::int, 0))
           = (COALESCE((lh.scores ->> '1')::int, 0) + COALESCE((lh.scores ->> '3')::int, 0))
          THEN ARRAY[0, 1, 2, 3]
        WHEN (COALESCE((lh.scores ->> '0')::int, 0) + COALESCE((lh.scores ->> '2')::int, 0))
           < (COALESCE((lh.scores ->> '1')::int, 0) + COALESCE((lh.scores ->> '3')::int, 0))
          THEN ARRAY[0, 2]
        ELSE ARRAY[1, 3]
      END
    ELSE (
      SELECT array_agg(t.seat ORDER BY t.seat)
      FROM (
        SELECT gs.seat, COALESCE((lh.scores ->> gs.seat::text)::int, 0) AS sc
        FROM generate_series(0, 3) AS gs(seat)
      ) AS t
      WHERE t.sc = (
        SELECT min(t2.sc) FROM (
          SELECT COALESCE((lh.scores ->> gs2.seat::text)::int, 0) AS sc
          FROM generate_series(0, 3) AS gs2(seat)
        ) AS t2
      )
    ) END AS winner_seats
  FROM last_hand AS lh
  JOIN public.okey_rooms AS r ON r.id = lh.room_id
),
match_agg AS (
  SELECT rp.bot_profile_id,
    count(*)::int AS matches_played,
    count(*) FILTER (WHERE rp.seat_no = ANY (rr.winner_seats))::int AS matches_won,
    min(COALESCE((rr.scores ->> rp.seat_no::text)::int, 0)) AS best_match_score,
    sum(COALESCE((rr.scores ->> rp.seat_no::text)::int, 0))::bigint AS total_final_score
  FROM room_result AS rr
  JOIN public.okey_room_players AS rp
    ON rp.room_id = rr.room_id AND rp.bot_profile_id IS NOT NULL
  GROUP BY rp.bot_profile_id
)
INSERT INTO public.okey_bot_stats (
  bot_profile_id, matches_played, matches_won,
  hands_played, hands_won, total_final_score, best_match_score
)
SELECT
  COALESCE(h.bot_profile_id, ma.bot_profile_id),
  COALESCE(ma.matches_played, 0),
  COALESCE(ma.matches_won, 0),
  COALESCE(h.hands_played, 0),
  COALESCE(h.hands_won, 0),
  COALESCE(ma.total_final_score, 0),
  ma.best_match_score
FROM hand_agg AS h
FULL OUTER JOIN match_agg AS ma ON ma.bot_profile_id = h.bot_profile_id
ON CONFLICT (bot_profile_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3) okey_bot_public_stats — ARTIK GERÇEK VERİYİ OKUR
-- -----------------------------------------------------------------------------
-- Aynı imza, aynı dönüş şekli: leaderboard ve profil kartı bu fonksiyonu hiç
-- değiştirmeden kullanmaya devam eder (bkz. dosya başlığı — tek kaynak).
CREATE OR REPLACE FUNCTION public.okey_bot_public_stats(p_bot_profile_id uuid)
RETURNS TABLE(
  points int,
  matches_played int,
  matches_won int,
  hands_played int,
  hands_won int,
  best_match_score int
)
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT
    -- 1000 − ortalama final skoru (bkz. dosya başlığı). Hiç oynamamış bir
    -- bot için 1000 (starting_points ile aynı) — insan tarafındaki "cüzdan
    -- henüz hiç işlem görmedi" durumunun karşılığı.
    GREATEST(0, 1000 - ROUND(
      COALESCE(s.total_final_score, 0)::numeric
        / NULLIF(COALESCE(s.matches_played, 0), 0)
    ))::int,
    COALESCE(s.matches_played, 0),
    COALESCE(s.matches_won, 0),
    COALESCE(s.hands_played, 0),
    COALESCE(s.hands_won, 0),
    s.best_match_score
  FROM (SELECT 1) AS one
  LEFT JOIN public.okey_bot_stats AS s ON s.bot_profile_id = p_bot_profile_id
$fn$;

COMMENT ON FUNCTION public.okey_bot_public_stats(uuid) IS
  'Bir bot kimliğinin GERÇEK oyun istatistikleri (okey_bot_stats''tan). Puan, botun gerçek final skorlarının ortalamasından türetilir çünkü botun cüzdanı yoktur (ekonominin dışındadır) — bkz. dosya başlığı. Skor tablosu (okey_leaderboard) ile profil kartı (okey_profile_card) aynı sayıları göstersin diye tek kaynak burasıdır.';

REVOKE ALL ON FUNCTION public.okey_bot_public_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_public_stats(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) okey_internal_record_hand_stats — BOT KOLTUĞU DA SAYILIR
-- -----------------------------------------------------------------------------
-- Gövde live sürümden taşındı; TEK EKLENEN insan döngüsünden SONRAKİ bot
-- döngüsüdür. İnsan dalı (satır satır) DEĞİŞMEDİ.
CREATE OR REPLACE FUNCTION public.okey_internal_record_hand_stats(
  p_room_id uuid,
  p_winner_seat smallint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player record;
BEGIN
  FOR v_player IN
    SELECT rp.user_id, rp.seat_no FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL
  LOOP
    INSERT INTO public.okey_stats AS st (user_id, hands_played, hands_won)
    VALUES (
      v_player.user_id, 1,
      CASE WHEN p_winner_seat IS NOT NULL AND v_player.seat_no = p_winner_seat
           THEN 1 ELSE 0 END
    )
    ON CONFLICT (user_id) DO UPDATE SET
      hands_played = st.hands_played + 1,
      hands_won = st.hands_won
        + CASE WHEN p_winner_seat IS NOT NULL
                 AND EXCLUDED.user_id IN (
                   SELECT rp2.user_id FROM public.okey_room_players rp2
                   WHERE rp2.room_id = p_room_id AND rp2.seat_no = p_winner_seat
                 )
               THEN 1 ELSE 0 END,
      updated_at = now();
  END LOOP;

  -- YENİ: BOT KOLTUKLARI (kullanıcı isteği, 2026-09-13 "botlarında gerçek
  -- verileri göster"). İnsan dalıyla aynı elin aynı sonucunu, ayrı tabloya
  -- yazar — bkz. dosya başlığı.
  FOR v_player IN
    SELECT rp.bot_profile_id, rp.seat_no FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.bot_profile_id IS NOT NULL
  LOOP
    INSERT INTO public.okey_bot_stats AS bs (bot_profile_id, hands_played, hands_won)
    VALUES (
      v_player.bot_profile_id, 1,
      CASE WHEN p_winner_seat IS NOT NULL AND v_player.seat_no = p_winner_seat
           THEN 1 ELSE 0 END
    )
    ON CONFLICT (bot_profile_id) DO UPDATE SET
      hands_played = bs.hands_played + 1,
      hands_won = bs.hands_won
        + CASE WHEN p_winner_seat IS NOT NULL
                 AND EXCLUDED.bot_profile_id IN (
                   SELECT rp2.bot_profile_id FROM public.okey_room_players rp2
                   WHERE rp2.room_id = p_room_id AND rp2.seat_no = p_winner_seat
                 )
               THEN 1 ELSE 0 END,
      updated_at = now();
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_record_hand_stats(uuid, smallint)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5) okey_internal_award_match — BOT KOLTUĞU DA SAYILIR
-- -----------------------------------------------------------------------------
-- Gövde live sürümden BİREBİR taşındı (ekonomi/pot mantığı TEK BİR SATIRI
-- bile değişmedi — bkz. 20260908190001). TEK EKLENEN, mevcut "İSTATİSTİKLER
-- / SKOR TABLOSU" döngüsünden SONRAKİ bot döngüsüdür.
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

  -- YENİ — BOT KOLTUKLARI (kullanıcı isteği, 2026-09-13). Ekonomiye
  -- (pot/komisyon/kasa) DOKUNMAZ — yukarıdaki hiçbir hesap değişmedi; bu
  -- döngü yalnızca GÖRÜNEN istatistiği gerçek maç sonucundan besler.
  FOR v_player IN
    SELECT rp.bot_profile_id, rp.seat_no FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.bot_profile_id IS NOT NULL
  LOOP
    v_score := COALESCE((p_final_scores ->> v_player.seat_no::text)::int, 0);

    INSERT INTO public.okey_bot_stats AS bs (
      bot_profile_id, matches_played, matches_won,
      total_final_score, best_match_score
    ) VALUES (
      v_player.bot_profile_id, 1,
      CASE WHEN v_player.seat_no = ANY(v_winner_seats) THEN 1 ELSE 0 END,
      v_score, v_score
    )
    ON CONFLICT (bot_profile_id) DO UPDATE SET
      matches_played = bs.matches_played + 1,
      matches_won = bs.matches_won + EXCLUDED.matches_won,
      total_final_score = bs.total_final_score + EXCLUDED.total_final_score,
      best_match_score = LEAST(
        COALESCE(bs.best_match_score, EXCLUDED.best_match_score),
        EXCLUDED.best_match_score
      ),
      updated_at = now();
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_award_match(uuid, jsonb)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

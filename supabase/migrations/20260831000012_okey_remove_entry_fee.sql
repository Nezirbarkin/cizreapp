-- =============================================================================
-- 101 Okey Plus — BAHİS (masa ücreti / entry fee) KALDIRILDI
-- -----------------------------------------------------------------------------
-- İSTENEN: Oyuncular masaya puan yatırmasın, kazanan pot almasın.
-- Oyun oynamak puan MALİYETİ ve puan ÖDÜLÜ içermez.
--
-- NE DEĞİŞİYOR:
--   1) create_okey_room artık entry_fee parametresi ALMIYOR (imza değişti).
--      Parametreyi bırakıp sessizce yok saymak yanıltıcı olurdu; bu yüzden
--      tamamen kaldırıldı ve istemci de buna göre güncellendi.
--   2) join_okey_room bakiye kontrolü yapmıyor — masaya katılmak bedava.
--   3) okey_internal_collect_entry_fees artık hiçbir şey tahsil etmiyor.
--   4) okey_internal_award_match pot dağıtmıyor ve pottan komisyon kesmiyor.
--
-- NE DEĞİŞMİYOR (bilinçli):
--   * okey_rooms.entry_fee KOLONU ve geçmiş okey_points_ledger /
--     okey_house_revenue satırları OLDUĞU GİBİ KALIR. Geçmişi geriye dönük
--     silmek muhasebeyi bozar; eski maçların gerçekten bahisli oynandığı
--     kaydı doğru olarak durmalıdır.
--   * Oda kurma ücreti (room_creation_fee) ve onun sistem kazancı DEVAM EDER
--     — kullanıcı yalnızca bahsin kaldırılmasını istedi.
--   * İstatistikler/skor tablosu (okey_stats) çalışmaya devam eder; yalnızca
--     total_points_won artık artmaz, matches_won ve best_match_score sürer.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- Bekleyen odalardaki bahis sıfırlanır (yarıda kalmış oda tahsilat yapmasın).
-- Biten odalara DOKUNULMAZ — onların geçmişi olduğu gibi kalır.
-- -----------------------------------------------------------------------------
UPDATE public.okey_rooms
SET entry_fee = 0
WHERE entry_fee <> 0
  AND status IN ('waiting', 'ready', 'in_progress')
  AND NOT entry_fee_collected;

COMMENT ON COLUMN public.okey_rooms.entry_fee IS
  'ARTIK KULLANILMIYOR — bahis kaldırıldı, yeni odalarda daima 0. Kolon yalnızca geçmiş maçların kaydı için duruyor.';

-- -----------------------------------------------------------------------------
-- create_okey_room: entry_fee parametresi kaldırıldı
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text, text, int);
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text, text);

CREATE FUNCTION public.create_okey_room(
  p_is_private boolean DEFAULT false,
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz',
  p_assist_mode text DEFAULT 'yardimli'
)
RETURNS public.okey_rooms
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_join_code text;
  v_settings public.okey_settings%ROWTYPE;
  v_wallet public.okey_wallets%ROWTYPE;
  v_room_fee int;
  v_seat smallint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF public.okey_is_banned(v_uid) THEN
    RAISE EXCEPTION 'APP:okey_banned' USING ERRCODE = '42501';
  END IF;
  IF p_game_mode NOT IN ('katlamasiz', 'katlamali') THEN
    RAISE EXCEPTION 'APP:invalid_game_mode' USING ERRCODE = '22023';
  END IF;
  IF p_team_mode NOT IN ('essiz', 'esli') THEN
    RAISE EXCEPTION 'APP:invalid_team_mode' USING ERRCODE = '22023';
  END IF;
  IF p_assist_mode NOT IN ('yardimli', 'yardimsiz') THEN
    RAISE EXCEPTION 'APP:invalid_assist_mode' USING ERRCODE = '22023';
  END IF;

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;
  v_room_fee := COALESCE(v_settings.room_creation_fee, 0);

  -- Yalnızca ODA KURMA ücreti için bakiye gerekir (bahis kaldırıldı)
  IF v_room_fee > 0 THEN
    v_wallet := public.okey_internal_ensure_wallet(v_uid);
    IF v_wallet.points < v_room_fee THEN
      RAISE EXCEPTION 'APP:insufficient_points | mevcut: %, gerekli: %',
        v_wallet.points, v_room_fee USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_is_private THEN
    v_join_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  END IF;

  INSERT INTO public.okey_rooms (
    created_by, is_private, join_code, max_score, turn_seconds,
    game_mode, team_mode, assist_mode, entry_fee
  ) VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20),
    p_game_mode, p_team_mode, p_assist_mode,
    0  -- BAHİS KALDIRILDI: yeni odalarda daima 0
  ) RETURNING * INTO v_room;

  -- SİSTEM KAZANCI: yalnızca oda kurma ücreti
  IF v_room_fee > 0 THEN
    PERFORM public.okey_internal_add_points(
      v_uid, -v_room_fee, 'room_fee', v_room.id::text
    );
    INSERT INTO public.okey_house_revenue (source, amount, room_id, user_id, ref)
    VALUES ('room_fee', v_room_fee, v_room.id, v_uid, v_room.id::text)
    ON CONFLICT DO NOTHING;
  END IF;

  FOR v_seat IN 0..3 LOOP
    INSERT INTO public.okey_room_players (room_id, seat_no, user_id, joined_at, is_ready)
    VALUES (
      v_room.id, v_seat,
      CASE WHEN v_seat = 0 THEN v_uid ELSE NULL END,
      CASE WHEN v_seat = 0 THEN now() ELSE NULL END,
      false
    );
  END LOOP;

  RETURN v_room;
END;
$$;
REVOKE ALL ON FUNCTION public.create_okey_room(boolean, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean, text, text, text)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- join_okey_room: bahis bakiye kontrolü kaldırıldı — katılmak bedava
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_okey_room(
  p_room_id uuid DEFAULT NULL,
  p_join_code text DEFAULT NULL
)
-- DİKKAT: dönüş kolon adları (r_room_id / r_seat_no) BİREBİR korunmalı —
-- istemci bu adlarla okuyor ve değiştirilirse Postgres de reddeder.
RETURNS TABLE(r_room_id uuid, r_seat_no smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_seat smallint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF public.okey_is_banned(v_uid) THEN
    RAISE EXCEPTION 'APP:okey_banned' USING ERRCODE = '42501';
  END IF;
  IF p_room_id IS NULL AND p_join_code IS NULL THEN
    RAISE EXCEPTION 'APP:room_or_code_required' USING ERRCODE = '22023';
  END IF;

  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE (p_room_id IS NOT NULL AND r.id = p_room_id)
     OR (p_join_code IS NOT NULL AND r.join_code = upper(p_join_code))
  FOR UPDATE;

  IF v_room.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_room.status <> 'waiting' THEN
    RAISE EXCEPTION 'APP:room_not_joinable' USING ERRCODE = 'P0001';
  END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_room.id AND rp.user_id = v_uid;
  IF v_seat IS NOT NULL THEN
    RETURN QUERY SELECT v_room.id, v_seat;
    RETURN;
  END IF;

  -- BAHİS KALDIRILDI: masaya katılmak için puan gerekmez

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_room.id AND rp.user_id IS NULL AND NOT rp.is_bot
  ORDER BY rp.seat_no LIMIT 1 FOR UPDATE;

  IF v_seat IS NULL THEN
    RAISE EXCEPTION 'APP:room_full' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.okey_room_players
  SET user_id = v_uid, joined_at = now(), is_ready = false, left_at = NULL
  WHERE room_id = v_room.id AND seat_no = v_seat;

  RETURN QUERY SELECT v_room.id, v_seat;
END;
$$;
REVOKE ALL ON FUNCTION public.join_okey_room(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_okey_room(uuid, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_collect_entry_fees: artık hiçbir şey tahsil etmez
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_collect_entry_fees(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- BAHİS KALDIRILDI. Fonksiyon, el başlangıcındaki çağrı zinciri bozulmasın
  -- diye duruyor ama hiçbir puan tahsil etmiyor.
  RETURN;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_collect_entry_fees(uuid)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_award_match: pot ve komisyon kaldırıldı, istatistikler kaldı
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
  v_winner_seat int;
  v_player record;
  v_winner_seats int[] := ARRAY[]::int[];
  v_team_a int;
  v_team_b int;
BEGIN
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id;
  IF v_room.id IS NULL THEN RETURN; END IF;

  -- KAZANAN(LAR) — puan ödülü için değil, istatistik/skor tablosu için
  IF v_room.team_mode = 'esli' THEN
    v_team_a := COALESCE((p_final_scores ->> '0')::int, 0)
              + COALESCE((p_final_scores ->> '2')::int, 0);
    v_team_b := COALESCE((p_final_scores ->> '1')::int, 0)
              + COALESCE((p_final_scores ->> '3')::int, 0);
    IF v_team_a <= v_team_b THEN
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
        v_winner_seat := v_seat;
      END IF;
    END LOOP;
    v_winner_seats := ARRAY[v_winner_seat];
  END IF;

  -- BAHİS KALDIRILDI: pot dağıtımı ve komisyon YOK.

  -- İSTATİSTİKLER / SKOR TABLOSU (puan ödülü olmadan da anlamlı)
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
      0,  -- bahis yok, puan ödülü yok
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

NOTIFY pgrst, 'reload schema';

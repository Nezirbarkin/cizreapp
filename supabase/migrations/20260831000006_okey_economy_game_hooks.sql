-- =============================================================================
-- 101 Okey Plus — Ekonominin oyuna bağlanması
-- -----------------------------------------------------------------------------
--   1) create_okey_room: giriş ücreti (bahis) parametresi
--   2) Maçın İLK eli başlarken her insan oyuncudan giriş ücreti düşülür
--   3) Maç bitince POT kazanana verilir + istatistikler güncellenir
--   4) Her el sonunda el istatistikleri işlenir
--
-- Kazanan = maç sonu KÜMÜLATİF CEZA PUANI EN DÜŞÜK olan oyuncu
-- (101 Okey'de düşük skor iyidir).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- Maçın giriş ücretinin tahsil edilip edilmediği (tekrar tahsili önler)
ALTER TABLE public.okey_rooms
  ADD COLUMN IF NOT EXISTS entry_fee_collected boolean NOT NULL DEFAULT false;

-- -----------------------------------------------------------------------------
-- create_okey_room: entry_fee ile
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text, text);
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text, text, int);

CREATE FUNCTION public.create_okey_room(
  p_is_private boolean DEFAULT false,
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz',
  p_assist_mode text DEFAULT 'yardimli',
  p_entry_fee int DEFAULT 0
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
  IF COALESCE(p_entry_fee, 0) < 0 THEN
    RAISE EXCEPTION 'APP:invalid_entry_fee' USING ERRCODE = '22023';
  END IF;

  -- Kurucu giriş ücretini karşılayabiliyor mu? (masa başlarken tahsil edilir)
  IF COALESCE(p_entry_fee, 0) > 0 THEN
    v_wallet := public.okey_internal_ensure_wallet(v_uid);
    IF v_wallet.points < p_entry_fee THEN
      RAISE EXCEPTION 'APP:insufficient_points | mevcut: %, gerekli: %',
        v_wallet.points, p_entry_fee USING ERRCODE = 'P0001';
    END IF;
  END IF;

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;
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
    p_game_mode, p_team_mode, p_assist_mode, COALESCE(p_entry_fee, 0)
  ) RETURNING * INTO v_room;

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
REVOKE ALL ON FUNCTION public.create_okey_room(boolean, text, text, text, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean, text, text, text, int)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- join_okey_room: giriş ücretini karşılayamayan katılamaz
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_okey_room(
  p_room_id uuid DEFAULT NULL,
  p_join_code text DEFAULT NULL
)
RETURNS TABLE(r_room_id uuid, r_seat_no smallint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_wallet public.okey_wallets%ROWTYPE;
  v_seat smallint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF public.okey_is_banned(v_uid) THEN
    RAISE EXCEPTION 'APP:okey_banned' USING ERRCODE = '42501';
  END IF;
  IF p_room_id IS NULL AND p_join_code IS NULL THEN
    RAISE EXCEPTION 'APP:room_id_or_join_code_required' USING ERRCODE = '22023';
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

  IF v_room.entry_fee > 0 THEN
    v_wallet := public.okey_internal_ensure_wallet(v_uid);
    IF v_wallet.points < v_room.entry_fee THEN
      RAISE EXCEPTION 'APP:insufficient_points | mevcut: %, gerekli: %',
        v_wallet.points, v_room.entry_fee USING ERRCODE = 'P0001';
    END IF;
  END IF;

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
-- okey_internal_collect_entry_fees: maçın ilk eli başlarken bir kez tahsil eder
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_collect_entry_fees(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_room public.okey_rooms%ROWTYPE;
  v_player record;
BEGIN
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id;
  IF v_room.id IS NULL OR v_room.entry_fee <= 0 OR v_room.entry_fee_collected THEN
    RETURN;
  END IF;

  FOR v_player IN
    SELECT rp.user_id FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL
  LOOP
    PERFORM public.okey_internal_add_points(
      v_player.user_id, -v_room.entry_fee, 'entry_fee',
      p_room_id::text || ':' || v_player.user_id::text
    );
  END LOOP;

  UPDATE public.okey_rooms SET entry_fee_collected = true WHERE id = p_room_id;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_collect_entry_fees(uuid)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_award_match: maç bitince potu kazanana ver + istatistik
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
  v_winner_seat int;
  v_best int;
  v_seat int;
  v_score int;
  v_winner_user uuid;
  v_human_count int;
  v_pot bigint;
  v_player record;
BEGIN
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id;
  IF v_room.id IS NULL THEN RETURN; END IF;

  -- Kazanan: kümülatif ceza puanı EN DÜŞÜK koltuk
  v_best := NULL;
  FOR v_seat IN 0..3 LOOP
    v_score := COALESCE((p_final_scores ->> v_seat::text)::int, 0);
    IF v_best IS NULL OR v_score < v_best THEN
      v_best := v_score;
      v_winner_seat := v_seat;
    END IF;
  END LOOP;

  SELECT rp.user_id INTO v_winner_user FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id AND rp.seat_no = v_winner_seat;

  SELECT count(*)::int INTO v_human_count FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL;

  -- Pot: tahsil edilen giriş ücretlerinin toplamı
  v_pot := v_room.entry_fee::bigint * v_human_count;

  IF v_winner_user IS NOT NULL AND v_pot > 0 AND v_room.entry_fee_collected THEN
    PERFORM public.okey_internal_add_points(
      v_winner_user, v_pot, 'match_win', p_room_id::text
    );
  END IF;

  -- İstatistikler
  FOR v_player IN
    SELECT rp.user_id, rp.seat_no FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL
  LOOP
    v_score := COALESCE((p_final_scores ->> v_player.seat_no::text)::int, 0);

    INSERT INTO public.okey_stats AS st (
      user_id, matches_played, matches_won, total_points_won, best_match_score
    ) VALUES (
      v_player.user_id, 1,
      CASE WHEN v_player.user_id = v_winner_user THEN 1 ELSE 0 END,
      CASE WHEN v_player.user_id = v_winner_user THEN v_pot ELSE 0 END,
      v_score
    )
    ON CONFLICT (user_id) DO UPDATE SET
      matches_played = st.matches_played + 1,
      matches_won = st.matches_won
        + CASE WHEN EXCLUDED.user_id = v_winner_user THEN 1 ELSE 0 END,
      total_points_won = st.total_points_won
        + CASE WHEN EXCLUDED.user_id = v_winner_user THEN v_pot ELSE 0 END,
      best_match_score = LEAST(COALESCE(st.best_match_score, v_score), v_score),
      updated_at = now();
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_award_match(uuid, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_record_hand_stats: her el sonunda el istatistikleri
-- -----------------------------------------------------------------------------
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
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_record_hand_stats(uuid, smallint)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

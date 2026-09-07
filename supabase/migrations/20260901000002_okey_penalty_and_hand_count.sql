-- =============================================================================
-- 101 Okey Plus — OKEY ATMA CEZASI + EL SAYISIYLA MAÇ BİTİŞİ
-- -----------------------------------------------------------------------------
-- 1) Okey taşını ıskartaya atmak artık CEZALIDIR. Ceza, atan oyuncunun o elki
--    cezasına eklenir; miktarı admin panelinden ayarlanabilir (varsayılan 101).
--    Botlar okeyi zaten hiç atmaz (bkz. okey_internal_bot_pick_discard).
--
-- 2) Maç, kümülatif skor barajına ulaşınca BİTTİĞİ GİBİ, oda kurulurken
--    seçilen EL SAYISI dolduğunda da biter.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- okey_internal_discard_for_seat: OKEY atılırsa ceza yaz
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_discard_for_seat(
  p_match_id uuid,
  p_seat smallint,
  p_tile jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE;
  v_tiles jsonb;
  v_idx int;
  i int;
  v_pile jsonb;
  v_next_seat smallint;
  v_is_open boolean;
  v_penalty int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = v_match.room_id;

  SELECT h.tiles, h.is_opening_done INTO v_tiles, v_is_open
  FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat FOR UPDATE;

  v_idx := NULL;
  FOR i IN 0 .. jsonb_array_length(v_tiles) - 1 LOOP
    IF v_tiles -> i = p_tile THEN
      v_idx := i;
      EXIT;
    END IF;
  END LOOP;
  IF v_idx IS NULL THEN
    RAISE EXCEPTION 'APP:tile_not_in_hand' USING ERRCODE = '22023';
  END IF;
  v_tiles := v_tiles - v_idx;

  UPDATE public.okey_player_hands SET tiles = v_tiles, updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  -- OKEY ATMA CEZASI ------------------------------------------------------
  -- Okey (veya onun yerine geçen sahte joker) ıskartaya atılırsa, atan
  -- oyuncunun bu elki cezasına sabit bir ceza eklenir. Ceza el sonunda
  -- skora yansır (bkz. okey_internal_finalize_hand).
  IF public.okey_tile_is_joker(p_tile, v_match.okey_tile) THEN
    SELECT COALESCE(s.okey_discard_penalty, 101) INTO v_penalty
    FROM public.okey_settings AS s WHERE s.id = true;

    IF COALESCE(v_penalty, 0) > 0 THEN
      UPDATE public.okey_player_hands
      SET penalty_points = penalty_points + v_penalty
      WHERE match_id = p_match_id AND seat_no = p_seat;
    END IF;
  END IF;

  v_pile := COALESCE(v_match.discard_piles -> p_seat::text, '[]'::jsonb)
            || jsonb_build_array(p_tile);

  UPDATE public.okey_matches
  SET discard_piles = jsonb_set(discard_piles, ARRAY[p_seat::text], v_pile)
  WHERE id = p_match_id;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
  VALUES (p_match_id, v_match.hand_no, p_seat, 'discard', p_tile);

  -- RULES.md §6: eli boşaldıysa ve el açılmışsa oyuncu BİTİRDİ
  IF jsonb_array_length(v_tiles) = 0 AND v_is_open THEN
    PERFORM public.okey_internal_finalize_hand(p_match_id, p_seat, p_tile);
    RETURN;
  END IF;

  UPDATE public.okey_player_hands
  SET opened_this_turn = false
  WHERE match_id = p_match_id AND seat_no = p_seat;

  v_next_seat := (p_seat + 1) % 4;
  UPDATE public.okey_matches
  SET turn_seat = v_next_seat,
      turn_phase = 'draw',
      turn_token = gen_random_uuid(),
      turn_deadline = now() + make_interval(secs => v_room.turn_seconds)
  WHERE id = p_match_id;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_discard_for_seat(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_finalize_hand: cezaları skora ekle + EL SAYISIYLA maç bitişi
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_finalize_hand(
  p_match_id uuid,
  p_winner_seat smallint,
  p_last_tile jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE;
  v_winner public.okey_player_hands%ROWTYPE;
  v_h public.okey_player_hands%ROWTYPE;
  v_multiplier int := 1;
  v_with_okey boolean := false;
  v_elden boolean := false;
  v_with_pairs boolean := false;
  v_win_label text := NULL;
  v_base int;
  v_hand_scores jsonb := '{}'::jsonb;
  v_new_scores jsonb;
  v_seat int;
  v_max_cum int := 0;
  v_hands_played int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE r.id = v_match.room_id FOR UPDATE;

  IF p_winner_seat IS NOT NULL THEN
    SELECT h.* INTO v_winner FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = p_winner_seat;

    v_with_okey := p_last_tile IS NOT NULL
                   AND public.okey_tile_is_joker(p_last_tile, v_match.okey_tile);
    v_elden := COALESCE(v_winner.opened_this_turn, false);
    v_with_pairs := COALESCE(v_winner.opened_with_pairs, false);

    v_multiplier := 1;
    IF v_with_okey THEN v_multiplier := v_multiplier * 2; END IF;
    IF v_elden THEN v_multiplier := v_multiplier * 2; END IF;
    IF v_with_pairs THEN v_multiplier := v_multiplier * 2; END IF;

    v_win_label := CASE
      WHEN v_elden AND v_with_okey THEN 'elden_okey'
      WHEN v_elden THEN 'elden'
      WHEN v_with_okey THEN 'okey'
      WHEN v_with_pairs THEN 'cift'
      ELSE 'normal'
    END;
  END IF;

  -- Her koltuk için ceza (RULES.md §7) + bu elde toplanan EK CEZALAR
  FOR v_h IN
    SELECT h.* FROM public.okey_player_hands AS h WHERE h.match_id = p_match_id
  LOOP
    IF p_winner_seat IS NOT NULL AND v_h.seat_no = p_winner_seat THEN
      -- Kazanan bile okey attıysa cezasını öder
      v_hand_scores := jsonb_set(
        v_hand_scores, ARRAY[v_h.seat_no::text],
        to_jsonb(-101 + COALESCE(v_h.penalty_points, 0))
      );
      CONTINUE;
    END IF;

    IF NOT v_h.is_opening_done THEN
      v_base := CASE WHEN v_h.went_for_pairs THEN 404 ELSE 202 END;
    ELSIF v_h.opened_with_pairs THEN
      v_base := public.okey_hand_penalty_value(v_h.tiles, v_match.okey_tile) * 2;
    ELSE
      v_base := public.okey_hand_penalty_value(v_h.tiles, v_match.okey_tile);
    END IF;

    v_hand_scores := jsonb_set(
      v_hand_scores, ARRAY[v_h.seat_no::text],
      to_jsonb(v_base * v_multiplier + COALESCE(v_h.penalty_points, 0))
    );
  END LOOP;

  -- Kümülatif skor
  v_new_scores := v_match.scores;
  FOR v_seat IN 0..3 LOOP
    v_new_scores := jsonb_set(
      v_new_scores,
      ARRAY[v_seat::text],
      to_jsonb(
        COALESCE((v_match.scores ->> v_seat::text)::int, 0)
        + COALESCE((v_hand_scores ->> v_seat::text)::int, 0)
      )
    );
    v_max_cum := GREATEST(v_max_cum,
                          COALESCE((v_new_scores ->> v_seat::text)::int, 0));
  END LOOP;

  INSERT INTO public.okey_scores_history
    (match_id, hand_no, seat_no, user_id, points, reason)
  SELECT p_match_id, v_match.hand_no, rp.seat_no, rp.user_id,
         COALESCE((v_hand_scores ->> rp.seat_no::text)::int, 0),
         COALESCE(v_win_label, 'deste_bitti')
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.user_id IS NOT NULL;

  UPDATE public.okey_matches
  SET status = 'finished',
      winner_seat = p_winner_seat,
      win_type = v_win_label,
      scores = v_new_scores,
      finished_at = now()
  WHERE id = p_match_id;

  IF p_winner_seat IS NOT NULL THEN
    INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
    VALUES (p_match_id, v_match.hand_no, p_winner_seat, 'declare_win');
  END IF;

  -- MAÇ BİTİŞİ: puan barajı DOLDU ya da seçilen EL SAYISI oynandı
  v_hands_played := v_match.hand_no;

  IF v_max_cum >= v_room.max_score
     OR v_hands_played >= COALESCE(v_room.total_hands, 3) THEN
    UPDATE public.okey_rooms SET status = 'finished', updated_at = now()
    WHERE id = v_room.id;
  ELSE
    PERFORM public.start_okey_hand(v_room.id);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_finalize_hand(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- create_okey_room: EL SAYISI parametresi
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text, text);

CREATE FUNCTION public.create_okey_room(
  p_is_private boolean DEFAULT false,
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz',
  p_assist_mode text DEFAULT 'yardimli',
  p_total_hands int DEFAULT 3
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
  IF COALESCE(p_total_hands, 3) < 1 OR COALESCE(p_total_hands, 3) > 20 THEN
    RAISE EXCEPTION 'APP:invalid_total_hands' USING ERRCODE = '22023';
  END IF;

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;
  v_room_fee := COALESCE(v_settings.room_creation_fee, 0);

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
    game_mode, team_mode, assist_mode, entry_fee, total_hands
  ) VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20),
    p_game_mode, p_team_mode, p_assist_mode,
    0,                          -- BAHİS KALDIRILDI
    COALESCE(p_total_hands, 3)  -- kaç el oynanacak
  ) RETURNING * INTO v_room;

  IF v_room_fee > 0 THEN
    PERFORM public.okey_internal_add_points(
      v_uid, -v_room_fee, 'room_fee', v_room.id::text
    );
    INSERT INTO public.okey_house_revenue (source, amount, room_id, user_id, ref)
    VALUES ('room_fee', v_room_fee, v_room.id, v_uid, v_room.id::text)
    ON CONFLICT DO NOTHING;
  END IF;

  FOR v_seat IN 0..3 LOOP
    INSERT INTO public.okey_room_players
      (room_id, seat_no, user_id, joined_at, is_ready)
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

NOTIFY pgrst, 'reload schema';

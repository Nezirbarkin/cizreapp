-- =============================================================================
-- 101 Okey Plus — v2 / Adım 3: el açma, oda modları, deste tükenmesi
-- -----------------------------------------------------------------------------
--   §3 okey_lay_meld: 101 puan / 5 çift barajı, katlamalı ve eşli istisnaları
--   §5 create_okey_room: katlamasız/katlamalı × eşsiz/eşli seçimi
--   §7 okey_set_went_for_pairs: "çifte gidiyorum" beyanı (404 cezasının şartı)
--   Deste tükenirse el kazanansız biter (herkes kendi cezasını alır)
--   okey_declare_win KALDIRILIR — bitiş artık son taşı atmakla olur (§6)
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- create_okey_room: mod seçimiyle
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_okey_room(boolean);
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text);

CREATE FUNCTION public.create_okey_room(
  p_is_private boolean DEFAULT false,
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz'
)
RETURNS public.okey_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_join_code text;
  v_settings public.okey_settings%ROWTYPE;
  v_seat smallint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_game_mode NOT IN ('katlamasiz', 'katlamali') THEN
    RAISE EXCEPTION 'APP:invalid_game_mode' USING ERRCODE = '22023';
  END IF;
  IF p_team_mode NOT IN ('essiz', 'esli') THEN
    RAISE EXCEPTION 'APP:invalid_team_mode' USING ERRCODE = '22023';
  END IF;

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;

  IF p_is_private THEN
    v_join_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  END IF;

  INSERT INTO public.okey_rooms (
    created_by, is_private, join_code, max_score, turn_seconds, game_mode, team_mode
  )
  VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20),
    p_game_mode, p_team_mode
  )
  RETURNING * INTO v_room;

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
REVOKE ALL ON FUNCTION public.create_okey_room(boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean, text, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_set_went_for_pairs: "çifte gidiyorum" beyanı (RULES.md §7 → 404 cezası)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_set_went_for_pairs(uuid, boolean);

CREATE FUNCTION public.okey_set_went_for_pairs(p_match_id uuid, p_value boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  UPDATE public.okey_player_hands AS h
  SET went_for_pairs = p_value
  WHERE h.match_id = p_match_id
    AND h.user_id = v_uid
    AND NOT h.is_opening_done;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:cannot_change_after_opening' USING ERRCODE = 'P0001';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_set_went_for_pairs(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_set_went_for_pairs(uuid, boolean) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_lay_meld: seri/grup VEYA çift ile açma + sonraki turlarda ek açma
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_lay_meld(uuid, jsonb);
DROP FUNCTION IF EXISTS public.okey_lay_meld(uuid, jsonb, boolean);

CREATE FUNCTION public.okey_lay_meld(
  p_match_id uuid,
  p_groups jsonb,
  p_is_pairs boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_hand public.okey_player_hands%ROWTYPE;
  v_flat jsonb := '[]'::jsonb;
  v_group jsonb;
  v_points int := 0;
  v_pairs int := 0;
  v_remaining jsonb;
  v_tile jsonb;
  v_idx int;
  v_search int;
  v_req record;
  v_first_open boolean;
  i int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_groups) <> 'array' OR jsonb_array_length(p_groups) = 0 THEN
    RAISE EXCEPTION 'APP:groups_required' USING ERRCODE = '22023';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id FOR UPDATE;
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_match.status <> 'in_progress' THEN
    RAISE EXCEPTION 'APP:match_finished' USING ERRCODE = 'P0001';
  END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid;
  IF v_seat IS NULL THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;
  IF v_seat IS DISTINCT FROM v_match.turn_seat OR v_match.turn_phase <> 'discard' THEN
    RAISE EXCEPTION 'APP:not_your_turn' USING ERRCODE = '42501';
  END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat FOR UPDATE;
  IF v_hand.match_id IS NULL THEN
    RAISE EXCEPTION 'APP:hand_not_found' USING ERRCODE = 'P0001';
  END IF;

  v_first_open := NOT v_hand.is_opening_done;

  -- Açılış türü tutarlılığı: çift açan oyuncu çiftle devam eder
  IF NOT v_first_open AND v_hand.opened_with_pairs <> p_is_pairs THEN
    RAISE EXCEPTION 'APP:opening_type_mismatch' USING ERRCODE = 'P0001';
  END IF;

  -- Grupları doğrula ve puan/çift say
  FOR i IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
    v_group := p_groups -> i;
    IF p_is_pairs THEN
      IF NOT public.okey_is_valid_pair(v_group, v_match.okey_tile) THEN
        RAISE EXCEPTION 'APP:invalid_pair' USING ERRCODE = '22023';
      END IF;
      v_pairs := v_pairs + 1;
    ELSE
      IF NOT public.okey_is_valid_meld(v_group, v_match.okey_tile) THEN
        RAISE EXCEPTION 'APP:invalid_meld' USING ERRCODE = '22023';
      END IF;
      v_points := v_points + public.okey_meld_points(v_group, v_match.okey_tile);
    END IF;
    v_flat := v_flat || v_group;
  END LOOP;

  -- İlk açılışta baraj kontrolü (RULES.md §3/§5)
  IF v_first_open THEN
    SELECT * INTO v_req FROM public.okey_required_opening(p_match_id, v_seat);
    IF p_is_pairs THEN
      IF v_pairs < v_req.min_pairs THEN
        RAISE EXCEPTION 'APP:pairs_below_threshold | gerekli: %, senin: %',
          v_req.min_pairs, v_pairs USING ERRCODE = 'P0001';
      END IF;
    ELSE
      IF v_points < v_req.min_points THEN
        RAISE EXCEPTION 'APP:points_below_threshold | gerekli: %, senin: %',
          v_req.min_points, v_points USING ERRCODE = 'P0001';
      END IF;
    END IF;
  END IF;

  -- Taşları elden düş
  v_remaining := v_hand.tiles;
  FOR i IN 0 .. jsonb_array_length(v_flat) - 1 LOOP
    v_tile := v_flat -> i;
    v_idx := NULL;
    FOR v_search IN 0 .. jsonb_array_length(v_remaining) - 1 LOOP
      IF v_remaining -> v_search = v_tile THEN
        v_idx := v_search;
        EXIT;
      END IF;
    END LOOP;
    IF v_idx IS NULL THEN
      RAISE EXCEPTION 'APP:tile_not_in_hand' USING ERRCODE = '22023';
    END IF;
    v_remaining := v_remaining - v_idx;
  END LOOP;

  UPDATE public.okey_player_hands
  SET tiles = v_remaining,
      is_opening_done = true,
      opened_with_pairs = CASE WHEN v_first_open THEN p_is_pairs ELSE opened_with_pairs END,
      opened_this_turn = CASE WHEN v_first_open THEN true ELSE opened_this_turn END,
      opened_at_hand_no = COALESCE(opened_at_hand_no, v_match.hand_no),
      updated_at = now()
  WHERE match_id = p_match_id AND seat_no = v_seat;

  FOR i IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
    v_group := p_groups -> i;
    INSERT INTO public.okey_table_melds (match_id, hand_no, laid_by_seat, meld_type, tiles)
    VALUES (
      p_match_id, v_match.hand_no, v_seat,
      CASE
        WHEN p_is_pairs THEN 'pair'
        WHEN public.okey_is_valid_run(v_group, v_match.okey_tile) THEN 'run'
        ELSE 'set'
      END,
      v_group
    );
  END LOOP;

  -- Katlamalı mod barajını yükselt (RULES.md §5)
  IF v_first_open THEN
    UPDATE public.okey_matches
    SET highest_opening_points = GREATEST(highest_opening_points, v_points),
        highest_opening_pairs = GREATEST(highest_opening_pairs, v_pairs)
    WHERE id = p_match_id;
  END IF;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'lay_meld');
END;
$$;
REVOKE ALL ON FUNCTION public.okey_lay_meld(uuid, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_lay_meld(uuid, jsonb, boolean) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_draw_for_seat: deste tükenirse el kazanansız biter
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_draw_for_seat(
  p_match_id uuid,
  p_seat smallint,
  p_source text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_drawn jsonb;
  v_deck jsonb;
  v_prev_seat smallint;
  v_prev_pile jsonb;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;

  IF p_source = 'deck' THEN
    IF v_match.deck_remaining <= 0 THEN
      -- RULES.md kapsamı dışı köşe durum: deste bitti, el kazanansız kapanır
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN NULL;
    END IF;

    SELECT d.remaining_deck INTO v_deck FROM public.okey_match_decks AS d
    WHERE d.match_id = p_match_id FOR UPDATE;

    v_drawn := v_deck -> 0;
    v_deck := v_deck - 0;

    UPDATE public.okey_match_decks SET remaining_deck = v_deck WHERE match_id = p_match_id;
    UPDATE public.okey_matches
    SET deck_remaining = deck_remaining - 1, turn_phase = 'discard'
    WHERE id = p_match_id;

    INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
    VALUES (p_match_id, v_match.hand_no, p_seat, 'draw_deck', v_drawn);
  ELSE
    v_prev_seat := (p_seat + 3) % 4;
    v_prev_pile := v_match.discard_piles -> v_prev_seat::text;
    IF v_prev_pile IS NULL OR jsonb_array_length(v_prev_pile) = 0 THEN
      RAISE EXCEPTION 'APP:discard_pile_empty' USING ERRCODE = 'P0001';
    END IF;

    v_drawn := v_prev_pile -> (jsonb_array_length(v_prev_pile) - 1);
    v_prev_pile := v_prev_pile - (jsonb_array_length(v_prev_pile) - 1);

    UPDATE public.okey_matches
    SET discard_piles = jsonb_set(discard_piles, ARRAY[v_prev_seat::text], v_prev_pile),
        turn_phase = 'discard'
    WHERE id = p_match_id;

    INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
    VALUES (p_match_id, v_match.hand_no, p_seat, 'draw_discard', v_drawn);
  END IF;

  UPDATE public.okey_player_hands
  SET tiles = tiles || jsonb_build_array(v_drawn), updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  RETURN v_drawn;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_draw_for_seat(uuid, smallint, text)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_declare_win KALDIRILIR — RULES.md §6: bitiş artık son taşı atmakla olur
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_declare_win(uuid, boolean, jsonb);

NOTIFY pgrst, 'reload schema';

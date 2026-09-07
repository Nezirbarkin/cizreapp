-- =============================================================================
-- 101 Okey Plus — v2 / Adım 2: dağıtım, el açma, bitiş ve puanlama
-- -----------------------------------------------------------------------------
-- RULES.md v2.0'ı hayata geçirir:
--   §1 Dağıtım: başlayana 22, diğerlerine 21 taş (eski: 15/14 — yanlıştı)
--   §3 El açma: 101 puan / 5 çift barajı; katlamalı ve eşli mod istisnaları
--   §6 Bitiş: ayrı "kazandım" beyanı YOK — eli boşaltıp son taşı atmak
--   §7 Puanlama: -101 / elde kalan / 202 / 404 / çift×2 / bitiş çarpanları
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- Oyuncunun bu TURDA açıp açmadığı (elden bitiş tespiti için)
ALTER TABLE public.okey_player_hands
  ADD COLUMN IF NOT EXISTS opened_this_turn boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.okey_player_hands.opened_this_turn IS
  'Oyuncu elini TAM BU TURDA ilk kez açtıysa true; turu bitince sıfırlanır. Elden bitiş (RULES.md §6) tespiti için.';

-- -----------------------------------------------------------------------------
-- start_okey_hand: 22/21 dağıtım (RULES.md §1)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_okey_hand(p_room_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_room public.okey_rooms%ROWTYPE;
  v_prev_match public.okey_matches%ROWTYPE;
  v_hand_no int := 1;
  v_dealer_seat smallint := 0;
  v_carried_scores jsonb := '{}'::jsonb;
  v_deck jsonb[] := ARRAY[]::jsonb[];
  v_indicator jsonb;
  v_okey_tile jsonb;
  v_match_id uuid;
  v_pos int;
  v_seat smallint;
  v_count int;
  v_hand jsonb;
  v_colors text[] := ARRAY['red', 'yellow', 'black', 'blue'];
  c text;
  n int;
BEGIN
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id FOR UPDATE;
  IF v_room.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_room.current_match_id IS NOT NULL THEN
    SELECT m.* INTO v_prev_match FROM public.okey_matches AS m WHERE m.id = v_room.current_match_id;
    IF v_prev_match.id IS NOT NULL THEN
      v_hand_no := v_prev_match.hand_no + 1;
      v_dealer_seat := (v_prev_match.dealer_seat + 1) % 4;
      v_carried_scores := v_prev_match.scores;
    END IF;
  END IF;

  -- 106 taş: 4 renk x 1-13 x 2 kopya + 2 sahte okey
  FOREACH c IN ARRAY v_colors LOOP
    FOR n IN 1..13 LOOP
      v_deck := v_deck || jsonb_build_object('color', c, 'number', n, 'isFalseJoker', false);
      v_deck := v_deck || jsonb_build_object('color', c, 'number', n, 'isFalseJoker', false);
    END LOOP;
  END LOOP;
  v_deck := v_deck || jsonb_build_object('color', NULL, 'number', NULL, 'isFalseJoker', true);
  v_deck := v_deck || jsonb_build_object('color', NULL, 'number', NULL, 'isFalseJoker', true);

  SELECT array_agg(t ORDER BY random()) INTO v_deck FROM unnest(v_deck) AS t;

  v_indicator := v_deck[1];
  v_okey_tile := jsonb_build_object(
    'color', v_indicator->>'color',
    'number', CASE WHEN (v_indicator->>'number')::int = 13 THEN 1 ELSE (v_indicator->>'number')::int + 1 END,
    'isFalseJoker', false
  );

  INSERT INTO public.okey_matches (
    room_id, hand_no, dealer_seat, turn_seat, turn_phase,
    indicator_tile, okey_tile, deck_remaining, scores,
    highest_opening_points, highest_opening_pairs
  ) VALUES (
    p_room_id, v_hand_no, v_dealer_seat, v_dealer_seat, 'discard',
    v_indicator, v_okey_tile, 0, v_carried_scores, 0, 0
  )
  RETURNING id INTO v_match_id;

  -- RULES.md §1: başlayan (dağıtan) 22, diğerleri 21 taş
  v_pos := 2;
  FOR v_seat IN 0..3 LOOP
    v_count := CASE WHEN v_seat = v_dealer_seat THEN 22 ELSE 21 END;
    v_hand := to_jsonb(v_deck[v_pos : v_pos + v_count - 1]);
    v_pos := v_pos + v_count;

    INSERT INTO public.okey_player_hands (match_id, seat_no, user_id, tiles)
    SELECT v_match_id, v_seat, rp.user_id, v_hand
    FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.seat_no = v_seat;
  END LOOP;

  INSERT INTO public.okey_match_decks (match_id, remaining_deck)
  VALUES (v_match_id, to_jsonb(v_deck[v_pos : array_length(v_deck, 1)]));

  UPDATE public.okey_matches
  SET deck_remaining = array_length(v_deck, 1) - v_pos + 1,
      turn_deadline = now() + make_interval(secs => v_room.turn_seconds)
  WHERE id = v_match_id;

  UPDATE public.okey_rooms
  SET status = 'in_progress', current_match_id = v_match_id, updated_at = now()
  WHERE id = p_room_id;

  RETURN v_match_id;
END;
$$;
REVOKE ALL ON FUNCTION public.start_okey_hand(uuid) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_required_opening: bu oyuncunun açması için gereken baraj
-- RULES.md §3/§5 — katlamalı ve eşli istisnaları burada toplanır.
-- Döner: (min_points, min_pairs)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_required_opening(
  p_match_id uuid,
  p_seat smallint
)
RETURNS TABLE(min_points int, min_pairs int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE;
  v_partner_open boolean := false;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = v_match.room_id;

  -- Eşli mod: eşi (karşıdaki oyuncu) açmışsa baraj aranmaz (RULES.md §5)
  IF v_room.team_mode = 'esli' THEN
    SELECT h.is_opening_done INTO v_partner_open
    FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = ((p_seat + 2) % 4)::smallint;
    IF COALESCE(v_partner_open, false) THEN
      RETURN QUERY SELECT 0, 1;
      RETURN;
    END IF;
  END IF;

  IF v_room.game_mode = 'katlamali' THEN
    RETURN QUERY SELECT
      GREATEST(101, v_match.highest_opening_points + 1),
      GREATEST(5, v_match.highest_opening_pairs + 1);
  ELSE
    RETURN QUERY SELECT 101, 5;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_required_opening(uuid, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_required_opening(uuid, smallint) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_finalize_hand: eli bitirir ve puanları yazar (RULES.md §7)
-- p_winner_seat NULL ise deste bitmiştir (kazanansız el).
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
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = v_match.room_id FOR UPDATE;

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

  -- Her koltuk için ceza (RULES.md §7)
  FOR v_h IN
    SELECT h.* FROM public.okey_player_hands AS h WHERE h.match_id = p_match_id
  LOOP
    IF p_winner_seat IS NOT NULL AND v_h.seat_no = p_winner_seat THEN
      v_hand_scores := jsonb_set(v_hand_scores, ARRAY[v_h.seat_no::text], to_jsonb(-101));
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
      v_hand_scores, ARRAY[v_h.seat_no::text], to_jsonb(v_base * v_multiplier)
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
    v_max_cum := GREATEST(v_max_cum, COALESCE((v_new_scores ->> v_seat::text)::int, 0));
  END LOOP;

  INSERT INTO public.okey_scores_history (match_id, hand_no, seat_no, user_id, points, reason)
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

  IF v_max_cum >= v_room.max_score THEN
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
-- okey_internal_discard_for_seat: atma + BİTİŞ kontrolü (RULES.md §6)
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

  v_pile := COALESCE(v_match.discard_piles -> p_seat::text, '[]'::jsonb) || jsonb_build_array(p_tile);

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

  -- Tur bitti: sıra ilerler, "bu turda açtı" bayrağı sıfırlanır
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

NOTIFY pgrst, 'reload schema';

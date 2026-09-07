-- =============================================================================
-- 101 Okey modülü — Faz A / Adım 6: kazanma iddiası, taş sayısı, süre-aşımı
-- -----------------------------------------------------------------------------
-- okey_declare_win: kazanma iddiasını HER ZAMAN sunucuda (oyuncunun gerçek
-- elini yeniden okuyarak) yeniden doğrular — client'tan gelen "kazandım"
-- beyanına asla güvenilmez. Bu, tüm tasarımın en kritik hile-önleme sınırı.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- okey_declare_win
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_declare_win(uuid, boolean, jsonb);

CREATE FUNCTION public.okey_declare_win(
  p_match_id uuid,
  p_is_pairs boolean,
  p_groups jsonb DEFAULT NULL
)
RETURNS public.okey_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE;
  v_seat smallint;
  v_hand public.okey_player_hands%ROWTYPE;
  v_is_elden boolean;
  v_moves_count int;
  v_multiplier int;
  v_win_label text;
  v_jokers int;
  v_hand_scores jsonb := '{}'::jsonb;
  v_new_cumulative jsonb;
  v_loser_hand public.okey_player_hands%ROWTYPE;
  v_loser_penalty int;
  v_max_cumulative int := 0;
  v_seat_cum int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id FOR UPDATE;
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_match.status <> 'in_progress' THEN
    RAISE EXCEPTION 'APP:match_finished' USING ERRCODE = 'P0001';
  END IF;

  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = v_match.room_id FOR UPDATE;

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

  -- elden: bu ele ait hiç 'discard' hamlesi olmamış olmalı (RULES.md §7)
  SELECT count(*) INTO v_moves_count FROM public.okey_moves
  WHERE match_id = p_match_id AND hand_no = v_match.hand_no AND action = 'discard';
  v_is_elden := (v_moves_count = 0);

  IF p_is_pairs THEN
    IF NOT public.okey_is_valid_pairs_hand(v_hand.tiles, v_match.okey_tile) THEN
      RAISE EXCEPTION 'APP:invalid_win' USING ERRCODE = '22023';
    END IF;
    v_jokers := public.okey_count_jokers(v_hand.tiles, v_match.okey_tile);
    v_multiplier := 2 * (CASE WHEN v_is_elden THEN 2 ELSE 1 END) * (CASE WHEN v_jokers >= 2 THEN 4 ELSE 1 END);
    v_win_label := CASE WHEN v_jokers >= 2 THEN 'cifte_okey' ELSE 'cift' END;
  ELSE
    IF p_groups IS NULL THEN
      RAISE EXCEPTION 'APP:groups_required' USING ERRCODE = '22023';
    END IF;

    DECLARE
      v_flat jsonb := '[]'::jsonb;
      v_remaining jsonb := v_hand.tiles;
      v_group jsonb;
      v_tile jsonb;
      v_idx int;
      gi int;
      ti int;
      si int;
    BEGIN
      FOR gi IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
        v_group := p_groups -> gi;
        IF NOT public.okey_is_valid_meld(v_group, v_match.okey_tile) THEN
          RAISE EXCEPTION 'APP:invalid_meld' USING ERRCODE = '22023';
        END IF;
        v_flat := v_flat || v_group;
      END LOOP;

      IF jsonb_array_length(v_flat) IS DISTINCT FROM jsonb_array_length(v_hand.tiles) THEN
        RAISE EXCEPTION 'APP:groups_do_not_match_hand' USING ERRCODE = '22023';
      END IF;

      FOR ti IN 0 .. jsonb_array_length(v_flat) - 1 LOOP
        v_tile := v_flat -> ti;
        v_idx := NULL;
        FOR si IN 0 .. jsonb_array_length(v_remaining) - 1 LOOP
          IF v_remaining -> si = v_tile THEN
            v_idx := si;
            EXIT;
          END IF;
        END LOOP;
        IF v_idx IS NULL THEN
          RAISE EXCEPTION 'APP:groups_do_not_match_hand' USING ERRCODE = '22023';
        END IF;
        v_remaining := v_remaining - v_idx;
      END LOOP;
    END;

    v_jokers := public.okey_count_jokers(v_hand.tiles, v_match.okey_tile);
    v_multiplier := 1 * (CASE WHEN v_is_elden THEN 2 ELSE 1 END) * (CASE WHEN v_jokers >= 2 THEN 4 ELSE 1 END);
    v_win_label := CASE
      WHEN v_jokers >= 2 THEN 'cifte_okey'
      WHEN v_is_elden THEN 'elden'
      ELSE 'normal'
    END;
  END IF;

  -- kaybedenlerin ceza puanı (RULES.md §8)
  FOR v_loser_hand IN
    SELECT h.* FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no <> v_seat
  LOOP
    v_loser_penalty := public.okey_hand_penalty_value(v_loser_hand.tiles, v_match.okey_tile) * v_multiplier;
    v_hand_scores := jsonb_set(v_hand_scores, ARRAY[v_loser_hand.seat_no::text], to_jsonb(v_loser_penalty));
  END LOOP;
  v_hand_scores := jsonb_set(v_hand_scores, ARRAY[v_seat::text], to_jsonb(0));

  -- kümülatif skor: elin başından devreden + bu elin puanı
  v_new_cumulative := v_match.scores;
  FOR v_seat_cum IN 0..3 LOOP
    v_new_cumulative := jsonb_set(
      v_new_cumulative,
      ARRAY[v_seat_cum::text],
      to_jsonb(
        COALESCE((v_match.scores ->> v_seat_cum::text)::int, 0)
        + COALESCE((v_hand_scores ->> v_seat_cum::text)::int, 0)
      )
    );
    v_max_cumulative := GREATEST(v_max_cumulative, COALESCE((v_new_cumulative ->> v_seat_cum::text)::int, 0));
  END LOOP;

  INSERT INTO public.okey_scores_history (match_id, hand_no, seat_no, user_id, points, reason)
  SELECT p_match_id, v_match.hand_no, rp.seat_no, rp.user_id,
         COALESCE((v_hand_scores ->> rp.seat_no::text)::int, 0),
         v_win_label
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id;

  UPDATE public.okey_matches
  SET status = 'finished',
      winner_seat = v_seat,
      win_type = v_win_label,
      scores = v_new_cumulative,
      finished_at = now()
  WHERE id = p_match_id;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'declare_win');

  IF v_max_cumulative >= v_room.max_score THEN
    UPDATE public.okey_rooms SET status = 'finished', updated_at = now() WHERE id = v_match.room_id;
  ELSE
    PERFORM public.start_okey_hand(v_match.room_id);
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_declare_win(uuid, boolean, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_declare_win(uuid, boolean, jsonb) TO authenticated;

-- -----------------------------------------------------------------------------
-- get_match_seat_tile_counts: rakip taş sayıları — gerçek taşlar asla dönmez
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_match_seat_tile_counts(uuid);

CREATE FUNCTION public.get_match_seat_tile_counts(p_match_id uuid)
RETURNS TABLE(seat_no smallint, tile_count int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT h.seat_no, h.tile_count
  FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id
    AND EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      JOIN public.okey_matches AS m ON m.room_id = rp.room_id
      WHERE m.id = p_match_id AND rp.user_id = (SELECT auth.uid())
    );
$$;

REVOKE ALL ON FUNCTION public.get_match_seat_tile_counts(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_match_seat_tile_counts(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_auto_advance: süresi dolan sırayı otomatik ilerletir. Herhangi bir
-- seated oyuncu tetikleyebilir; sunucu now() > turn_deadline'ı bağımsız
-- doğrular, çağıranın beyanına güvenmez.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_auto_advance(uuid);

CREATE FUNCTION public.okey_auto_advance(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_hand_tiles jsonb;
  v_tile jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id FOR UPDATE;
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_match.status <> 'in_progress' THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  IF v_match.turn_deadline IS NULL OR now() < v_match.turn_deadline THEN
    RETURN; -- henüz süre dolmadı, sessizce yok say
  END IF;

  v_seat := v_match.turn_seat;

  IF v_match.turn_phase = 'draw' THEN
    IF v_match.deck_remaining > 0 THEN
      PERFORM public.okey_internal_draw_for_seat(p_match_id, v_seat, 'deck');
    ELSE
      RETURN; -- deste bitmiş: elle müdahale gerektirir, Faz A kapsamı dışı
    END IF;
    SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  END IF;

  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  IF v_hand_tiles IS NOT NULL AND jsonb_array_length(v_hand_tiles) > 0 THEN
    v_tile := v_hand_tiles -> 0; -- elin ilk taşı otomatik atılır
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_tile);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_auto_advance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_auto_advance(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- 101 Okey modülü — Faz A / Adım 5: per/grup açma, gruba ekleme, kazanma
-- -----------------------------------------------------------------------------
-- okey_lay_meld / okey_add_to_meld / okey_declare_win: hepsi yalnızca
-- çağıranın kendi sırasında (turn_seat = kendi koltuğu) ve 'discard'
-- fazında (yani taşını çektikten sonra) çalışır — tıpkı gerçek oyunda
-- olduğu gibi, bir oyuncu yalnızca kendi sırasında elini düzenleyebilir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- okey_lay_meld: bir veya daha fazla per/grubu masaya açar (el açma dahil)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_lay_meld(uuid, jsonb);

CREATE FUNCTION public.okey_lay_meld(p_match_id uuid, p_groups jsonb)
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
  v_remaining jsonb;
  v_tile jsonb;
  v_idx int;
  v_search_idx int;
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

  FOR i IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
    v_group := p_groups -> i;
    IF NOT public.okey_is_valid_meld(v_group, v_match.okey_tile) THEN
      RAISE EXCEPTION 'APP:invalid_meld' USING ERRCODE = '22023';
    END IF;
    v_points := v_points + public.okey_meld_points(v_group, v_match.okey_tile);
    v_flat := v_flat || v_group;
  END LOOP;

  IF NOT v_hand.is_opening_done AND v_points < 101 THEN
    RAISE EXCEPTION 'APP:opening_requires_101' USING ERRCODE = 'P0001';
  END IF;

  -- taşları elden düş (her biri gerçekten elde bulunmalı)
  v_remaining := v_hand.tiles;
  FOR i IN 0 .. jsonb_array_length(v_flat) - 1 LOOP
    v_tile := v_flat -> i;
    v_idx := NULL;
    FOR v_search_idx IN 0 .. jsonb_array_length(v_remaining) - 1 LOOP
      IF v_remaining -> v_search_idx = v_tile THEN
        v_idx := v_search_idx;
        EXIT;
      END IF;
    END LOOP;
    IF v_idx IS NULL THEN
      RAISE EXCEPTION 'APP:tile_not_in_hand' USING ERRCODE = '22023';
    END IF;
    v_remaining := v_remaining - v_idx;
  END LOOP;

  UPDATE public.okey_player_hands
  SET tiles = v_remaining, is_opening_done = true, updated_at = now()
  WHERE match_id = p_match_id AND seat_no = v_seat;

  FOR i IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
    v_group := p_groups -> i;
    INSERT INTO public.okey_table_melds (match_id, hand_no, laid_by_seat, meld_type, tiles)
    VALUES (
      p_match_id, v_match.hand_no, v_seat,
      CASE WHEN public.okey_is_valid_run(v_group, v_match.okey_tile) THEN 'run' ELSE 'set' END,
      v_group
    );
  END LOOP;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'lay_meld');
END;
$$;

REVOKE ALL ON FUNCTION public.okey_lay_meld(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_lay_meld(uuid, jsonb) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_add_to_meld: eli açılmış bir oyuncu, masadaki herhangi bir per/gruba
-- elinden bir taş ekler (Okey 101 Plus paritesi — RULES.md §6)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_add_to_meld(uuid, bigint, jsonb);

CREATE FUNCTION public.okey_add_to_meld(p_match_id uuid, p_meld_id bigint, p_tile jsonb)
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
  v_meld public.okey_table_melds%ROWTYPE;
  v_new_tiles jsonb;
  v_remaining jsonb;
  v_idx int;
  i int;
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
  IF NOT v_hand.is_opening_done THEN
    RAISE EXCEPTION 'APP:opening_required' USING ERRCODE = 'P0001';
  END IF;

  SELECT tm.* INTO v_meld FROM public.okey_table_melds AS tm
  WHERE tm.id = p_meld_id AND tm.match_id = p_match_id FOR UPDATE;
  IF v_meld.id IS NULL THEN
    RAISE EXCEPTION 'APP:meld_not_found' USING ERRCODE = 'P0001';
  END IF;

  v_remaining := v_hand.tiles;
  v_idx := NULL;
  FOR i IN 0 .. jsonb_array_length(v_remaining) - 1 LOOP
    IF v_remaining -> i = p_tile THEN
      v_idx := i;
      EXIT;
    END IF;
  END LOOP;
  IF v_idx IS NULL THEN
    RAISE EXCEPTION 'APP:tile_not_in_hand' USING ERRCODE = '22023';
  END IF;

  v_new_tiles := v_meld.tiles || jsonb_build_array(p_tile);
  IF NOT public.okey_is_valid_meld(v_new_tiles, v_match.okey_tile) THEN
    RAISE EXCEPTION 'APP:invalid_meld_after_add' USING ERRCODE = '22023';
  END IF;

  v_remaining := v_remaining - v_idx;

  UPDATE public.okey_player_hands
  SET tiles = v_remaining, updated_at = now()
  WHERE match_id = p_match_id AND seat_no = v_seat;

  UPDATE public.okey_table_melds
  SET tiles = v_new_tiles, updated_at = now()
  WHERE id = p_meld_id;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'add_to_meld', p_tile);
END;
$$;

REVOKE ALL ON FUNCTION public.okey_add_to_meld(uuid, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_add_to_meld(uuid, bigint, jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';

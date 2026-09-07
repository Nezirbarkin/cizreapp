-- =============================================================================
-- 101 Okey Plus — OKEY ELDE KALMA CEZASI + BOTLAR İŞLEME YAPAR
-- -----------------------------------------------------------------------------
-- 1) OKEY ELDE KALIRSA CEZA
--    Okeyi ATMAK zaten cezalıydı. Artık el bittiğinde okey HÂLÂ ELDEYSE de
--    ceza yazılır. Böylece okey ne atılabilir ne de saklanabilir — gerçek
--    oyundaki gibi işlenmek zorundadır.
--    İki ceza da admin panelinden ayrı ayrı ayarlanabilir.
--
-- 2) BOTLAR ARTIK İŞLEME YAPAR
--    Bot açtıktan sonra elindeki taşları masadaki AÇIK PERLERE ekliyor
--    ("işlek"). Önceden yalnızca kendi perlerini açıyor, sonra elinde kalan
--    taşları tek tek atıyordu — gerçek bir oyuncu gibi davranmıyordu.
--    Gösterge çiftine ve normal çifte işleme YAPILMAZ (kural gereği).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- okey_internal_finalize_hand: OKEY ELDE KALMA cezası eklendi
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
  v_in_hand_penalty int;
  v_extra int;
  v_has_okey boolean;
  i int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE r.id = v_match.room_id FOR UPDATE;

  SELECT COALESCE(s.okey_in_hand_penalty, 101) INTO v_in_hand_penalty
  FROM public.okey_settings AS s WHERE s.id = true;

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

  FOR v_h IN
    SELECT h.* FROM public.okey_player_hands AS h WHERE h.match_id = p_match_id
  LOOP
    -- OKEY ELDE KALMA CEZASI: el bittiğinde okey hâlâ elindeyse eklenir.
    -- (Okey ATMA cezası zaten atma anında yazılıyor — bkz.
    --  okey_internal_discard_for_seat. İkisi farklı olaylardır ve ikisi de
    --  penalty_points üzerinden toplanır.)
    v_has_okey := false;
    IF v_h.tiles IS NOT NULL THEN
      FOR i IN 0 .. GREATEST(jsonb_array_length(v_h.tiles) - 1, -1) LOOP
        IF public.okey_tile_is_joker(v_h.tiles -> i, v_match.okey_tile) THEN
          v_has_okey := true;
          EXIT;
        END IF;
      END LOOP;
    END IF;

    v_extra := COALESCE(v_h.penalty_points, 0)
             + CASE WHEN v_has_okey THEN COALESCE(v_in_hand_penalty, 0)
                    ELSE 0 END;

    IF p_winner_seat IS NOT NULL AND v_h.seat_no = p_winner_seat THEN
      v_hand_scores := jsonb_set(
        v_hand_scores, ARRAY[v_h.seat_no::text], to_jsonb(-101 + v_extra));
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
      to_jsonb(v_base * v_multiplier + v_extra));
  END LOOP;

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
-- okey_internal_bot_process_tiles: bot elindeki taşları AÇIK PERLERE işler
--
-- Gösterge çiftine ve normal çifte dokunulmaz. Her tur birden çok taş
-- işlenebilir; el boşalırsa oyuncu BİTİRİR.
-- Döner: işlenen taş sayısı.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_bot_process_tiles(
  p_match_id uuid,
  p_seat smallint
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_hand public.okey_player_hands%ROWTYPE;
  v_meld public.okey_table_melds%ROWTYPE;
  v_tile jsonb;
  v_new_tiles jsonb;
  v_processed int := 0;
  v_progress boolean := true;
  v_idx int;
  i int;
  v_guard int := 0;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.id IS NULL OR v_match.status <> 'in_progress' THEN
    RETURN 0;
  END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat;
  IF v_hand.match_id IS NULL OR NOT v_hand.is_opening_done THEN
    RETURN 0; -- açmadan işleme yapılamaz
  END IF;

  -- Bir tur boyunca işleyebildiği sürece devam et
  WHILE v_progress LOOP
    v_progress := false;
    v_guard := v_guard + 1;
    EXIT WHEN v_guard > 25; -- güvenlik freni

    SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = p_seat;
    EXIT WHEN v_hand.tiles IS NULL OR jsonb_array_length(v_hand.tiles) = 0;

    -- ATILACAK BİR TAŞ KALMALI: eli tamamen boşaltmak bitiş demektir ve
    -- bitiş yalnızca ATMA ile olur (RULES.md §6). Bu yüzden son taş
    -- işlenmez; bot onu atarak bitirir.
    EXIT WHEN jsonb_array_length(v_hand.tiles) <= 1;

    FOR v_meld IN
      SELECT tm.* FROM public.okey_table_melds AS tm
      WHERE tm.match_id = p_match_id
        AND tm.hand_no = v_match.hand_no
        AND tm.meld_type IN ('run', 'set')   -- çiftlere işleme yok
      ORDER BY tm.id
    LOOP
      FOR i IN 0 .. jsonb_array_length(v_hand.tiles) - 1 LOOP
        v_tile := v_hand.tiles -> i;

        -- Okey işlenebilir ama elde tutmak da cezalı; yine de en son çare
        -- olarak değerlendirilir (doğal taşlar önce denendiği için sıra
        -- doğal olarak onlara gelir).
        v_new_tiles := v_meld.tiles || jsonb_build_array(v_tile);
        CONTINUE WHEN NOT public.okey_is_valid_meld(
          v_new_tiles, v_match.okey_tile);

        -- Taşı elden düş
        v_idx := i;
        UPDATE public.okey_player_hands
        SET tiles = tiles - v_idx, updated_at = now()
        WHERE match_id = p_match_id AND seat_no = p_seat;

        UPDATE public.okey_table_melds
        SET tiles = v_new_tiles, updated_at = now()
        WHERE id = v_meld.id;

        INSERT INTO public.okey_moves
          (match_id, hand_no, seat_no, action, tile)
        VALUES (p_match_id, v_match.hand_no, p_seat, 'add_to_meld', v_tile);

        v_processed := v_processed + 1;
        v_progress := true;
        EXIT; -- eli değişti, baştan tara
      END LOOP;

      EXIT WHEN v_progress;
    END LOOP;
  END LOOP;

  RETURN v_processed;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_bot_process_tiles(uuid, smallint)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_bot_take_turn: AÇ -> İŞLE -> AT
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_bot_take_turn(uuid);

CREATE FUNCTION public.okey_bot_take_turn(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_prev_seat smallint;
  v_is_bot boolean;
  v_hand_tiles jsonb;
  v_groups jsonb;
  v_tile jsonb;
  v_pile jsonb;
  v_top jsonb;
  v_source text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m
  WHERE m.id = p_match_id FOR UPDATE;
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

  v_seat := v_match.turn_seat;

  SELECT rp.is_bot INTO v_is_bot FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.seat_no = v_seat;
  IF NOT COALESCE(v_is_bot, false) THEN
    RETURN;
  END IF;

  -- 1) ÇEKME — soldakinin ıskartası işe yarıyorsa oradan, yoksa desteden
  IF v_match.turn_phase = 'draw' THEN
    SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

    v_source := 'deck';
    v_prev_seat := (v_seat + 3) % 4;
    v_pile := v_match.discard_piles -> v_prev_seat::text;

    IF v_pile IS NOT NULL AND jsonb_array_length(v_pile) > 0 THEN
      v_top := v_pile -> (jsonb_array_length(v_pile) - 1);
      IF public.okey_internal_bot_wants_discard(
           v_hand_tiles, v_top, v_match.okey_tile) THEN
        v_source := 'discard';
      END IF;
    END IF;

    IF v_source = 'deck' AND v_match.deck_remaining <= 0 THEN
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN;
    END IF;

    PERFORM public.okey_internal_draw_for_seat(p_match_id, v_seat, v_source);
    SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  END IF;

  -- 2) AÇMA
  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  v_groups := public.okey_internal_find_melds(v_hand_tiles, v_match.okey_tile);
  IF jsonb_array_length(COALESCE(v_groups, '[]'::jsonb)) > 0 THEN
    PERFORM public.okey_internal_lay_groups_for_seat(p_match_id, v_seat, v_groups);
  END IF;

  -- 3) İŞLEME — açık perlere taş ekle ("işlek")
  PERFORM public.okey_internal_bot_process_tiles(p_match_id, v_seat);

  -- El bu arada bitmiş olabilir
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.status <> 'in_progress' THEN
    RETURN;
  END IF;

  -- 4) ATMA — okey asla atılmaz
  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  IF v_hand_tiles IS NOT NULL AND jsonb_array_length(v_hand_tiles) > 0 THEN
    v_tile := public.okey_internal_bot_pick_discard(v_hand_tiles, v_match.okey_tile);
    IF v_tile IS NOT NULL THEN
      PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_tile);
    END IF;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_bot_take_turn(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_take_turn(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

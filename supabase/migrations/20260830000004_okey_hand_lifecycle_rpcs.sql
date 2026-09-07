-- =============================================================================
-- 101 Okey modülü — Faz A / Adım 4: el başlatma (dağıtım) + sıra/hamle RPC'leri
-- -----------------------------------------------------------------------------
-- start_okey_hand: yeni bir el başlatır (deste oluşturma/karıştırma/dağıtım
-- SADECE burada, sunucu tarafında yapılır). set_okey_ready tüm koltuklar
-- hazır olduğunda bunu otomatik çağırır; okey_declare_win de bir sonraki
-- ele geçerken tekrar çağırır (bkz. sonraki migration).
--
-- okey_internal_draw_for_seat / okey_internal_discard_for_seat: gerçek
-- mutasyonu yapan iç fonksiyonlar. Bilerek p_seat parametresi alırlar
-- (auth.uid()'den DEĞİL) çünkü okey_auto_advance gibi bir çağıran, süresi
-- dolan BAŞKA bir koltuk adına hareket edebilmeli — auth.uid() her zaman
-- çağıranın kendi kimliğini verir, bu yüzden "hangi koltuk hareket ediyor"
-- kararı her zaman dış (public) fonksiyonda verilip iç fonksiyona parametre
-- olarak geçirilir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- start_okey_hand — internal (authenticated'a açılmaz)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.start_okey_hand(uuid);

CREATE FUNCTION public.start_okey_hand(p_room_id uuid)
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

  -- 106 taşlık deste: 4 renk x 1-13 x 2 kopya + 2 sahte okey
  FOREACH c IN ARRAY v_colors LOOP
    FOR n IN 1..13 LOOP
      v_deck := v_deck || jsonb_build_object('color', c, 'number', n, 'isFalseJoker', false);
      v_deck := v_deck || jsonb_build_object('color', c, 'number', n, 'isFalseJoker', false);
    END LOOP;
  END LOOP;
  v_deck := v_deck || jsonb_build_object('color', NULL, 'number', NULL, 'isFalseJoker', true);
  v_deck := v_deck || jsonb_build_object('color', NULL, 'number', NULL, 'isFalseJoker', true);

  SELECT array_agg(t ORDER BY random()) INTO v_deck FROM unnest(v_deck) AS t;

  -- gösterge: destenin ilk taşı
  v_indicator := v_deck[1];
  v_okey_tile := jsonb_build_object(
    'color', v_indicator->>'color',
    'number', CASE WHEN (v_indicator->>'number')::int = 13 THEN 1 ELSE (v_indicator->>'number')::int + 1 END,
    'isFalseJoker', false
  );

  INSERT INTO public.okey_matches (
    room_id, hand_no, dealer_seat, turn_seat, turn_phase,
    indicator_tile, okey_tile, deck_remaining, scores
  ) VALUES (
    p_room_id, v_hand_no, v_dealer_seat, v_dealer_seat, 'discard',
    v_indicator, v_okey_tile, 0, v_carried_scores
  )
  RETURNING id INTO v_match_id;

  -- dağıtım: dağıtan 15, diğerleri 14 taş. gösterge slot 1'i kullandı.
  v_pos := 2;
  FOR v_seat IN 0..3 LOOP
    v_count := CASE WHEN v_seat = v_dealer_seat THEN 15 ELSE 14 END;
    v_hand := to_jsonb(v_deck[v_pos : v_pos + v_count - 1]);
    v_pos := v_pos + v_count;

    INSERT INTO public.okey_player_hands (match_id, seat_no, user_id, tiles)
    SELECT v_match_id, v_seat, rp.user_id, v_hand
    FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.seat_no = v_seat;
  END LOOP;

  -- kalan taşlar sunucu-only deste tablosuna yazılır (hiçbir client okuyamaz)
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
-- set_okey_ready — koltuk hazır/hazır-değil işaretler; 4/4 hazırsa eli başlatır
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.set_okey_ready(uuid, boolean);

CREATE FUNCTION public.set_okey_ready(p_room_id uuid, p_ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_seat_count int;
  v_all_ready boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id FOR UPDATE;
  IF v_room.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_room.status <> 'waiting' THEN
    RAISE EXCEPTION 'APP:room_not_waiting' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.okey_room_players
  SET is_ready = p_ready
  WHERE room_id = p_room_id AND user_id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) FILTER (WHERE user_id IS NOT NULL),
         bool_and(is_ready) FILTER (WHERE user_id IS NOT NULL)
    INTO v_seat_count, v_all_ready
  FROM public.okey_room_players
  WHERE room_id = p_room_id;

  IF v_seat_count = 4 AND v_all_ready THEN
    PERFORM public.start_okey_hand(p_room_id);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_okey_ready(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_okey_ready(uuid, boolean) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_draw_for_seat — internal
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_internal_draw_for_seat(uuid, smallint, text);

CREATE FUNCTION public.okey_internal_draw_for_seat(
  p_match_id uuid,
  p_seat smallint,
  p_source text -- 'deck' | 'discard'
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
      RAISE EXCEPTION 'APP:deck_empty' USING ERRCODE = 'P0001';
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

REVOKE ALL ON FUNCTION public.okey_internal_draw_for_seat(uuid, smallint, text) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_discard_for_seat — internal
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_internal_discard_for_seat(uuid, smallint, jsonb);

CREATE FUNCTION public.okey_internal_discard_for_seat(
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
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = v_match.room_id;

  SELECT h.tiles INTO v_tiles FROM public.okey_player_hands AS h
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
  v_next_seat := (p_seat + 1) % 4;

  UPDATE public.okey_matches
  SET discard_piles = jsonb_set(discard_piles, ARRAY[p_seat::text], v_pile),
      turn_seat = v_next_seat,
      turn_phase = 'draw',
      turn_token = gen_random_uuid(),
      turn_deadline = now() + make_interval(secs => v_room.turn_seconds)
  WHERE id = p_match_id;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
  VALUES (p_match_id, v_match.hand_no, p_seat, 'discard', p_tile);
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_discard_for_seat(uuid, smallint, jsonb) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_take_turn_action — public: çekme/atma. Maç satırını FOR UPDATE ile
-- kilitler, sırayı doğrular, sonra internal fonksiyonlara delege eder.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_take_turn_action(uuid, text, jsonb, uuid);

CREATE FUNCTION public.okey_take_turn_action(
  p_match_id uuid,
  p_action text,
  p_tile jsonb DEFAULT NULL,
  p_expected_turn_token uuid DEFAULT NULL
)
RETURNS public.okey_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_action NOT IN ('draw_deck', 'draw_discard', 'discard') THEN
    RAISE EXCEPTION 'APP:invalid_action' USING ERRCODE = '22023';
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
  IF v_seat IS DISTINCT FROM v_match.turn_seat THEN
    RAISE EXCEPTION 'APP:not_your_turn' USING ERRCODE = '42501';
  END IF;
  IF p_expected_turn_token IS NOT NULL AND p_expected_turn_token IS DISTINCT FROM v_match.turn_token THEN
    RAISE EXCEPTION 'APP:stale_turn' USING ERRCODE = '40001';
  END IF;

  IF p_action IN ('draw_deck', 'draw_discard') THEN
    IF v_match.turn_phase <> 'draw' THEN
      RAISE EXCEPTION 'APP:wrong_phase' USING ERRCODE = '22023';
    END IF;
    PERFORM public.okey_internal_draw_for_seat(
      p_match_id, v_seat, CASE WHEN p_action = 'draw_deck' THEN 'deck' ELSE 'discard' END
    );
  ELSE
    IF v_match.turn_phase <> 'discard' THEN
      RAISE EXCEPTION 'APP:wrong_phase' USING ERRCODE = '22023';
    END IF;
    IF p_tile IS NULL THEN
      RAISE EXCEPTION 'APP:tile_required' USING ERRCODE = '22023';
    END IF;
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, p_tile);
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_take_turn_action(uuid, text, jsonb, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_take_turn_action(uuid, text, jsonb, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

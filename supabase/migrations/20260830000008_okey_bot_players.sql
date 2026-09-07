-- =============================================================================
-- 101 Okey modülü — Faz A / Ek: bot (robot) oyuncu desteği
-- -----------------------------------------------------------------------------
-- Test kolaylığı için: bir oyuncu, odadaki boş koltukları botlarla
-- doldurabilir (okey_fill_with_bots). Botlar her zaman 'hazır' sayılır.
-- Sıra bir bota geldiğinde, odadaki HERHANGİ bir gerçek oyuncunun client'ı
-- okey_bot_take_turn'ü çağırarak botun basit hamlesini (desteden çek,
-- elin ilk taşını at) tetikler — bot hiçbir zaman per/grup açmaya veya
-- kazanmaya çalışmaz, sadece sırayı ilerletir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.okey_room_players
  ADD COLUMN IF NOT EXISTS is_bot boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.okey_room_players.is_bot IS
  'true ise bu koltuk gerçek bir kullanıcı değil, test amaçlı otomatik oynayan bir bot.';

-- -----------------------------------------------------------------------------
-- okey_fill_with_bots: çağıranın oturduğu odadaki boş koltukları botlarla
-- doldurur. Tüm koltuklar dolunca (insan+bot) set_okey_ready ile aynı
-- "4/4 hazır" mantığı burada da uygulanır.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_fill_with_bots(uuid);

CREATE FUNCTION public.okey_fill_with_bots(p_room_id uuid)
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
  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  UPDATE public.okey_room_players
  SET is_bot = true, is_ready = true, joined_at = now()
  WHERE room_id = p_room_id AND user_id IS NULL AND is_bot = false;

  SELECT count(*) FILTER (WHERE user_id IS NOT NULL OR is_bot),
         bool_and(is_ready) FILTER (WHERE user_id IS NOT NULL OR is_bot)
    INTO v_seat_count, v_all_ready
  FROM public.okey_room_players
  WHERE room_id = p_room_id;

  IF v_seat_count = 4 AND v_all_ready THEN
    PERFORM public.start_okey_hand(p_room_id);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_fill_with_bots(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_fill_with_bots(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- set_okey_ready güncellenir: doluluk sayımı artık bot koltuklarını da sayar
-- (aksi halde insan+bot karışık bir odada asla "4/4 hazır" tetiklenmez).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_okey_ready(p_room_id uuid, p_ready boolean)
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

  SELECT count(*) FILTER (WHERE user_id IS NOT NULL OR is_bot),
         bool_and(is_ready) FILTER (WHERE user_id IS NOT NULL OR is_bot)
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
-- start_okey_hand güncellenir: bot koltuklarına da (user_id NULL olsa dahi)
-- el dağıtılmalı. okey_player_hands.user_id NOT NULL olduğu için bot
-- koltuklarına dağıtırken user_id = NULL kabul edilemez; bunun yerine
-- odayı kuran kullanıcının id'si "vekil sahip" olarak kullanılmaz — bunun
-- yerine tabloyu bota izin verecek şekilde gevşetiyoruz (user_id nullable).
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_player_hands
  ALTER COLUMN user_id DROP NOT NULL;

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
    indicator_tile, okey_tile, deck_remaining, scores
  ) VALUES (
    p_room_id, v_hand_no, v_dealer_seat, v_dealer_seat, 'discard',
    v_indicator, v_okey_tile, 0, v_carried_scores
  )
  RETURNING id INTO v_match_id;

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
-- okey_bot_take_turn: sırası gelen koltuk bot ise, herhangi bir seated
-- gerçek oyuncu tetikleyebilir. Bot her zaman: (varsa) desteden çek,
-- elin ilk taşını at — hiç per/grup açmaya/kazanmaya çalışmaz.
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
  v_is_bot boolean;
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

  v_seat := v_match.turn_seat;

  SELECT rp.is_bot INTO v_is_bot FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.seat_no = v_seat;

  IF NOT COALESCE(v_is_bot, false) THEN
    RETURN; -- sıradaki koltuk bot değil, yapacak bir şey yok
  END IF;

  IF v_match.turn_phase = 'draw' THEN
    IF v_match.deck_remaining > 0 THEN
      PERFORM public.okey_internal_draw_for_seat(p_match_id, v_seat, 'deck');
    ELSE
      RETURN;
    END IF;
    SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  END IF;

  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  IF v_hand_tiles IS NOT NULL AND jsonb_array_length(v_hand_tiles) > 0 THEN
    v_tile := v_hand_tiles -> 0;
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_tile);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_bot_take_turn(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_take_turn(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

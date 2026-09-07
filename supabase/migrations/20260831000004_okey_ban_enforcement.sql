-- Okey yasağı: yasaklı kullanıcı oda kuramaz ve odaya katılamaz.
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.create_okey_room(
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
  IF p_is_private THEN
    v_join_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  END IF;

  INSERT INTO public.okey_rooms (
    created_by, is_private, join_code, max_score, turn_seconds,
    game_mode, team_mode, assist_mode
  ) VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20),
    p_game_mode, p_team_mode, p_assist_mode
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
REVOKE ALL ON FUNCTION public.create_okey_room(boolean, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean, text, text, text) TO authenticated;

-- join_okey_room: yasak kontrolü ekle
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

NOTIFY pgrst, 'reload schema';

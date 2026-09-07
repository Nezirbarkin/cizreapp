-- =============================================================================
-- 101 Okey Plus — Botlar masaya otururken PROFİL ALIR
-- -----------------------------------------------------------------------------
-- okey_fill_with_bots artık boş koltukları bot yaptıktan hemen sonra
-- okey_internal_assign_bot_profiles'i çağırır: botlar admin panelinde
-- tanımlanan ad ve avatarlarla masada görünür.
--
-- Profil havuzu boşsa hiçbir şey değişmez — botlar eski davranışla "Bot N"
-- olarak görünür. Yani bu ekleme geriye dönük uyumludur.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.okey_fill_with_bots(p_room_id uuid)
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

  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE r.id = p_room_id FOR UPDATE;
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

  -- Botlara admin panelindeki kimlikleri ata (havuz boşsa sessizce atlanır)
  PERFORM public.okey_internal_assign_bot_profiles(p_room_id);

  -- "botlarla doldur" tıklamak zaten hazır olduğunu ima eder
  UPDATE public.okey_room_players
  SET is_ready = true
  WHERE room_id = p_room_id AND user_id = v_uid;

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

NOTIFY pgrst, 'reload schema';

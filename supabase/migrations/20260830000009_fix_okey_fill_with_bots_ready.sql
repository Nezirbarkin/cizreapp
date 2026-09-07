-- =============================================================================
-- 101 Okey modülü — Faz A / Düzeltme: okey_fill_with_bots çağıranı hazır yapmıyordu
-- -----------------------------------------------------------------------------
-- HATA: okey_fill_with_bots, boş koltukları bota çevirip is_ready=true
-- yapıyordu ama ÇAĞIRANIN kendi koltuğu hâlâ is_ready=false kalıyordu
-- (create_okey_room ile oda kurulduğunda varsayılan is_ready=false).
-- Sonuç: "Botlarla Doldur"a basan tek oyuncu bile el otomatik başlamıyordu
-- çünkü bool_and(is_ready) hâlâ false dönüyordu — smoke testte (adım 7)
-- yakalandı.
--
-- ÇÖZÜM: fonksiyon artık botları doldururken çağıranın kendi koltuğunu da
-- is_ready=true yapıyor — "botlarla doldur" tıklamak zaten oynamaya hazır
-- olduğunu ima eder.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

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

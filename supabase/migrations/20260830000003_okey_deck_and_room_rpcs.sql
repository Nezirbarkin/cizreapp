-- =============================================================================
-- 101 Okey modülü — Faz A / Adım 3: sunucu-only deste tablosu + oda/lobi RPC'leri
-- -----------------------------------------------------------------------------
-- okey_match_decks: bir elin kalan (henüz çekilmemiş) taş sırası. RLS aktif
-- ama HİÇBİR SELECT/INSERT/UPDATE/DELETE policy'si yok — hiçbir client
-- (kendi hesabı dahil) bu satırı asla okuyamaz/yazamaz. Yalnızca tablo
-- sahibi (SECURITY DEFINER fonksiyonlar bu sahiplik altında çalışır) RLS'i
-- otomatik atlayarak erişebilir. Bu, deste sırasının hiçbir client'a hiç
-- ulaşmamasını garanti eder (hile önleme tasarımının bir parçası).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.okey_match_decks (
  match_id uuid PRIMARY KEY REFERENCES public.okey_matches(id) ON DELETE CASCADE,
  remaining_deck jsonb NOT NULL
);

COMMENT ON TABLE public.okey_match_decks IS
  'Sunucu-only: bir elin kalan (henüz çekilmemiş) taş sırası. RLS aktif, hiçbir policy yok — yalnızca tablo sahibi (SECURITY DEFINER fonksiyonlar) erişebilir.';

ALTER TABLE public.okey_match_decks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.okey_match_decks FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- create_okey_room: yeni oda + 4 koltuk satırı (seat 0 = kurucu), ayarlar
-- okey_settings'ten okunur.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_okey_room(boolean);

CREATE FUNCTION public.create_okey_room(p_is_private boolean DEFAULT false)
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

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;

  IF p_is_private THEN
    v_join_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  END IF;

  INSERT INTO public.okey_rooms (created_by, is_private, join_code, max_score, turn_seconds)
  VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20)
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

REVOKE ALL ON FUNCTION public.create_okey_room(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean) TO authenticated;

-- -----------------------------------------------------------------------------
-- join_okey_room: id veya davet koduyla boş bir koltuğa otur (idempotent)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.join_okey_room(uuid, text);

CREATE FUNCTION public.join_okey_room(
  p_room_id uuid DEFAULT NULL,
  p_join_code text DEFAULT NULL
)
RETURNS TABLE(r_room_id uuid, r_seat_no smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_seat smallint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
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
  WHERE rp.room_id = v_room.id AND rp.user_id IS NULL
  ORDER BY rp.seat_no
  LIMIT 1
  FOR UPDATE;

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

-- -----------------------------------------------------------------------------
-- leave_okey_room: yalnız 'waiting' odada; son kişi çıkarsa oda 'abandoned' olur
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.leave_okey_room(uuid);

CREATE FUNCTION public.leave_okey_room(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_remaining int;
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
  SET user_id = NULL, is_ready = false, left_at = now()
  WHERE room_id = p_room_id AND user_id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_remaining FROM public.okey_room_players
  WHERE room_id = p_room_id AND user_id IS NOT NULL;

  IF v_remaining = 0 THEN
    UPDATE public.okey_rooms SET status = 'abandoned', updated_at = now() WHERE id = p_room_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.leave_okey_room(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leave_okey_room(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- 101 Okey Plus — Yardımlı / Yardımsız mod
-- -----------------------------------------------------------------------------
-- Yardımlı modda istemci, oyuncunun rafındaki "işlenebilir" taşları (masadaki
-- açık bir pere eklenebilenleri) otomatik vurgular. Bu tamamen bir ARAYÜZ
-- kolaylığıdır — hiçbir gizli bilgi sızdırmaz, yalnızca oyuncunun zaten
-- gördüğü kendi taşları ile yine herkesin gördüğü masa perlerini karşılaştırır.
-- Yine de oda ayarı olarak tutulur ki masadaki herkes hangi modda oynandığını
-- bilsin (rozet olarak gösterilir).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.okey_rooms
  ADD COLUMN IF NOT EXISTS assist_mode text NOT NULL DEFAULT 'yardimli';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'okey_rooms_assist_mode_check'
  ) THEN
    ALTER TABLE public.okey_rooms
      ADD CONSTRAINT okey_rooms_assist_mode_check
      CHECK (assist_mode IN ('yardimli', 'yardimsiz'));
  END IF;
END;
$$;

COMMENT ON COLUMN public.okey_rooms.assist_mode IS
  'yardimli = istemci işlenebilir taşları vurgular; yardimsiz = ipucu yok. Yalnızca arayüz kolaylığı, gizli bilgi sızdırmaz.';

-- create_okey_room: assist_mode parametresi eklenir
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text);
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text, text);

CREATE FUNCTION public.create_okey_room(
  p_is_private boolean DEFAULT false,
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz',
  p_assist_mode text DEFAULT 'yardimli'
)
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
  )
  VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20),
    p_game_mode, p_team_mode, p_assist_mode
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

REVOKE ALL ON FUNCTION public.create_okey_room(boolean, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean, text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

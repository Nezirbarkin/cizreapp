-- =============================================================================
-- 101 Okey Plus — MASA SADECE PUANLA AÇILIR (en az 100)
-- -----------------------------------------------------------------------------
-- Ücretsiz masa artık YOK. Her masanın bir giriş puanı olmak zorunda ve bu
-- puan alt sınırın altında olamaz (varsayılan 100, admin panelinden
-- ayarlanabilir).
--
-- KURAL SUNUCUDA ZORUNLU: arayüzde 100 altını seçmek mümkün olmasa bile,
-- doğrudan RPC çağrısıyla ücretsiz masa açılamaz.
--
-- GEÇMİŞ ODALARA DOKUNULMAZ: eski odalarda entry_fee 0 olabilir; kolona
-- CHECK eklenmez, kural yalnızca YENİ oda kurarken uygulanır. Geçmişi geriye
-- dönük değiştirmek muhasebeyi bozardı.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS min_entry_fee int NOT NULL DEFAULT 100;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'okey_settings_min_entry_check'
  ) THEN
    ALTER TABLE public.okey_settings
      ADD CONSTRAINT okey_settings_min_entry_check
      CHECK (min_entry_fee >= 1);
  END IF;
END $$;

COMMENT ON COLUMN public.okey_settings.min_entry_fee IS
  'Bir masanın giriş puanı en az bu kadar olmalı. Ücretsiz masa açılamaz.';

-- -----------------------------------------------------------------------------
-- create_okey_room: giriş puanı ZORUNLU ve alt sınırın altında olamaz
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text, text, int, int);

CREATE FUNCTION public.create_okey_room(
  p_is_private boolean DEFAULT false,
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz',
  p_assist_mode text DEFAULT 'yardimli',
  p_total_hands int DEFAULT 3,
  p_entry_fee int DEFAULT 100
)
RETURNS public.okey_rooms
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_join_code text;
  v_settings public.okey_settings%ROWTYPE;
  v_wallet public.okey_wallets%ROWTYPE;
  v_room_fee int;
  v_entry int;
  v_min_entry int;
  v_needed bigint;
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
  IF COALESCE(p_total_hands, 3) < 1 OR COALESCE(p_total_hands, 3) > 20 THEN
    RAISE EXCEPTION 'APP:invalid_total_hands' USING ERRCODE = '22023';
  END IF;

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;
  v_room_fee := COALESCE(v_settings.room_creation_fee, 0);
  v_min_entry := GREATEST(COALESCE(v_settings.min_entry_fee, 100), 1);

  -- MASA SADECE PUANLA AÇILIR: alt sınırın altı reddedilir
  v_entry := COALESCE(p_entry_fee, 0);
  IF v_entry < v_min_entry THEN
    RAISE EXCEPTION 'APP:entry_fee_too_low | en az: %', v_min_entry
      USING ERRCODE = '22023';
  END IF;

  -- Kurucu hem oda ücretini hem KENDİ giriş ücretini karşılayabilmeli
  v_needed := v_room_fee::bigint + v_entry::bigint;
  IF v_needed > 0 THEN
    v_wallet := public.okey_internal_ensure_wallet(v_uid);
    IF v_wallet.points < v_needed THEN
      RAISE EXCEPTION 'APP:insufficient_points | mevcut: %, gerekli: %',
        v_wallet.points, v_needed USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_is_private THEN
    v_join_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  END IF;

  INSERT INTO public.okey_rooms (
    created_by, is_private, join_code, max_score, turn_seconds,
    game_mode, team_mode, assist_mode, entry_fee, total_hands
  ) VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20),
    p_game_mode, p_team_mode, p_assist_mode,
    v_entry,
    COALESCE(p_total_hands, 3)
  ) RETURNING * INTO v_room;

  IF v_room_fee > 0 THEN
    PERFORM public.okey_internal_add_points(
      v_uid, -v_room_fee, 'room_fee', v_room.id::text
    );
    INSERT INTO public.okey_house_revenue (source, amount, room_id, user_id, ref)
    VALUES ('room_fee', v_room_fee, v_room.id, v_uid, v_room.id::text)
    ON CONFLICT DO NOTHING;
  END IF;

  FOR v_seat IN 0..3 LOOP
    INSERT INTO public.okey_room_players
      (room_id, seat_no, user_id, joined_at, is_ready)
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
REVOKE ALL ON FUNCTION public.create_okey_room(boolean, text, text, text, int, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean, text, text, text, int, int)
  TO authenticated;

NOTIFY pgrst, 'reload schema';

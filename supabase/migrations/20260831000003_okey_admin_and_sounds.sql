-- =============================================================================
-- 101 Okey Plus — Faz F: Admin yönetimi + ses dosyası yönetimi
-- -----------------------------------------------------------------------------
--   1) okey-sounds storage bucket'ı (admin yükler, herkes dinler)
--   2) okey_sound_assets tablosu: hangi ses olayına hangi dosya bağlı
--   3) okey_bans tablosu: Okey'den yasaklı kullanıcılar
--   4) Admin RPC'leri: aktif masaları izleme, oyuncu atma, yasaklama, ayarlar
--
-- GİZLİLİK NOTU: Admin izleme fonksiyonları oyuncuların ELİNDEKİ TAŞLARI
-- ASLA döndürmez. Moderasyon amacıyla bile olsa okey_player_hands'e
-- dokunulmaz — hile-önleme sınırı admin için de geçerlidir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) Ses dosyaları için storage bucket
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'okey-sounds',
  'okey-sounds',
  true,
  2097152, -- 2 MB: kısa efektler için fazlasıyla yeterli
  ARRAY['audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/ogg', 'audio/aac']::text[]
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "okey_sounds_public_read" ON storage.objects;
CREATE POLICY "okey_sounds_public_read"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'okey-sounds');

DROP POLICY IF EXISTS "okey_sounds_admin_write" ON storage.objects;
CREATE POLICY "okey_sounds_admin_write"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'okey-sounds' AND public.is_admin());

DROP POLICY IF EXISTS "okey_sounds_admin_update" ON storage.objects;
CREATE POLICY "okey_sounds_admin_update"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'okey-sounds' AND public.is_admin());

DROP POLICY IF EXISTS "okey_sounds_admin_delete" ON storage.objects;
CREATE POLICY "okey_sounds_admin_delete"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'okey-sounds' AND public.is_admin());

-- -----------------------------------------------------------------------------
-- 2) Ses olayı -> dosya eşlemesi
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_sound_assets (
  sound_key text PRIMARY KEY,
  storage_path text NOT NULL,
  public_url text NOT NULL,
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_sound_assets IS
  'Okey ses olaylarının (draw/discard/laugh/...) admin tarafından yüklenmiş dosyaları. Tüm oyuncular okuyabilir; yalnız admin yazabilir.';

ALTER TABLE public.okey_sound_assets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS okey_sound_assets_select ON public.okey_sound_assets;
CREATE POLICY okey_sound_assets_select ON public.okey_sound_assets
  FOR SELECT TO authenticated USING (true);

REVOKE INSERT, UPDATE, DELETE ON public.okey_sound_assets FROM authenticated;

-- -----------------------------------------------------------------------------
-- 3) Okey yasakları
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_bans (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason text,
  banned_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  banned_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz
);

COMMENT ON TABLE public.okey_bans IS
  'Okey oyununa girişi yasaklı kullanıcılar. expires_at NULL ise süresizdir.';

ALTER TABLE public.okey_bans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS okey_bans_select_own ON public.okey_bans;
CREATE POLICY okey_bans_select_own ON public.okey_bans
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_admin());

REVOKE INSERT, UPDATE, DELETE ON public.okey_bans FROM authenticated;

-- Yasaklı kullanıcı oda kuramaz / katılamaz
CREATE OR REPLACE FUNCTION public.okey_is_banned(p_user_id uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.okey_bans AS b
    WHERE b.user_id = COALESCE(p_user_id, (SELECT auth.uid()))
      AND (b.expires_at IS NULL OR b.expires_at > now())
  );
$$;
REVOKE ALL ON FUNCTION public.okey_is_banned(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_is_banned(uuid) TO authenticated;

-- =============================================================================
-- ADMIN RPC'LERİ
-- =============================================================================

-- -----------------------------------------------------------------------------
-- admin_okey_overview: aktif masaların özeti (TAŞLAR DÖNMEZ)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_okey_overview();

CREATE FUNCTION public.admin_okey_overview()
RETURNS TABLE(
  room_id uuid,
  status text,
  game_mode text,
  team_mode text,
  assist_mode text,
  is_private boolean,
  hand_no int,
  turn_seat smallint,
  seated_count int,
  bot_count int,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    r.id,
    r.status,
    r.game_mode,
    r.team_mode,
    r.assist_mode,
    r.is_private,
    COALESCE(m.hand_no, 0),
    COALESCE(m.turn_seat, 0::smallint),
    (SELECT count(*)::int FROM public.okey_room_players rp
      WHERE rp.room_id = r.id AND rp.user_id IS NOT NULL),
    (SELECT count(*)::int FROM public.okey_room_players rp
      WHERE rp.room_id = r.id AND rp.is_bot),
    r.created_at
  FROM public.okey_rooms AS r
  LEFT JOIN public.okey_matches AS m ON m.id = r.current_match_id
  WHERE public.is_admin()
    AND r.status IN ('waiting', 'in_progress')
  ORDER BY r.created_at DESC
  LIMIT 100;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_overview() TO authenticated;

-- -----------------------------------------------------------------------------
-- admin_okey_room_players: bir odadaki oyuncular (yine TAŞLAR DÖNMEZ)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_okey_room_players(uuid);

CREATE FUNCTION public.admin_okey_room_players(p_room_id uuid)
RETURNS TABLE(
  seat_no smallint,
  user_id uuid,
  display_name text,
  is_bot boolean,
  is_ready boolean,
  last_seen_at timestamptz,
  tile_count int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    rp.seat_no,
    rp.user_id,
    COALESCE(p.full_name, p.username, '—'),
    rp.is_bot,
    rp.is_ready,
    rp.last_seen_at,
    COALESCE(h.tile_count, 0)
  FROM public.okey_room_players AS rp
  LEFT JOIN public.profiles AS p ON p.id = rp.user_id
  LEFT JOIN public.okey_matches AS m ON m.id =
    (SELECT r.current_match_id FROM public.okey_rooms r WHERE r.id = p_room_id)
  LEFT JOIN public.okey_player_hands AS h
    ON h.match_id = m.id AND h.seat_no = rp.seat_no
  WHERE public.is_admin() AND rp.room_id = p_room_id
  ORDER BY rp.seat_no;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_room_players(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_room_players(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- admin_okey_kick_player: oyuncuyu masadan çıkar (koltuğu bota devreder)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_okey_kick_player(uuid, smallint);

CREATE FUNCTION public.admin_okey_kick_player(p_room_id uuid, p_seat smallint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  -- Oyun sürüyorsa koltuk BOTA devredilir ki masa kilitlenmesin
  UPDATE public.okey_room_players
  SET user_id = NULL,
      is_bot = true,
      is_ready = true,
      left_at = now()
  WHERE room_id = p_room_id AND seat_no = p_seat;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_kick_player(uuid, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_kick_player(uuid, smallint) TO authenticated;

-- -----------------------------------------------------------------------------
-- admin_okey_set_ban / admin_okey_remove_ban
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_okey_set_ban(uuid, text, timestamptz);

CREATE FUNCTION public.admin_okey_set_ban(
  p_user_id uuid,
  p_reason text DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.okey_bans (user_id, reason, banned_by, expires_at)
  VALUES (p_user_id, p_reason, (SELECT auth.uid()), p_expires_at)
  ON CONFLICT (user_id) DO UPDATE
    SET reason = EXCLUDED.reason,
        banned_by = EXCLUDED.banned_by,
        banned_at = now(),
        expires_at = EXCLUDED.expires_at;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_set_ban(uuid, text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_set_ban(uuid, text, timestamptz) TO authenticated;

DROP FUNCTION IF EXISTS public.admin_okey_remove_ban(uuid);

CREATE FUNCTION public.admin_okey_remove_ban(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.okey_bans WHERE user_id = p_user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_remove_ban(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_remove_ban(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- admin_okey_update_settings: varsayılan max_score / sıra süresi
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_okey_update_settings(int, int);

CREATE FUNCTION public.admin_okey_update_settings(
  p_max_score int,
  p_turn_seconds int
)
RETURNS public.okey_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row public.okey_settings%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_max_score <= 0 OR p_turn_seconds <= 0 THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;

  UPDATE public.okey_settings
  SET default_max_score = p_max_score,
      default_turn_seconds = p_turn_seconds,
      updated_by = (SELECT auth.uid())
  WHERE id = true
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_update_settings(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_update_settings(int, int) TO authenticated;

-- -----------------------------------------------------------------------------
-- admin_okey_set_sound / admin_okey_clear_sound
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_okey_set_sound(text, text, text);

CREATE FUNCTION public.admin_okey_set_sound(
  p_sound_key text,
  p_storage_path text,
  p_public_url text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(p_sound_key), '') IS NULL
     OR NULLIF(trim(p_public_url), '') IS NULL THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.okey_sound_assets
    (sound_key, storage_path, public_url, updated_by, updated_at)
  VALUES
    (p_sound_key, p_storage_path, p_public_url, (SELECT auth.uid()), now())
  ON CONFLICT (sound_key) DO UPDATE
    SET storage_path = EXCLUDED.storage_path,
        public_url = EXCLUDED.public_url,
        updated_by = EXCLUDED.updated_by,
        updated_at = now();
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_set_sound(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_set_sound(text, text, text) TO authenticated;

DROP FUNCTION IF EXISTS public.admin_okey_clear_sound(text);

CREATE FUNCTION public.admin_okey_clear_sound(p_sound_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.okey_sound_assets WHERE sound_key = p_sound_key;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_clear_sound(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_clear_sound(text) TO authenticated;

NOTIFY pgrst, 'reload schema';

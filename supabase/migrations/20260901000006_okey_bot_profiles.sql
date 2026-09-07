-- =============================================================================
-- 101 Okey Plus — ADMIN TARAFINDAN YÖNETİLEN BOT PROFİLLERİ
-- -----------------------------------------------------------------------------
-- Botların şu ana kadar kimliği yoktu: masada hepsi "Bot 1", "Bot 2" diye
-- görünüyordu, avatarları da yoktu. Admin artık bot profilleri (ad + avatar)
-- oluşturabilir; masaya oturan botlar bu havuzdan rastgele seçilir ve gerçek
-- oyuncular gibi isim/resimle görünür.
--
-- Profil YOKSA davranış değişmez: bot yine "Bot N" olarak görünür. Yani bu
-- özellik tamamen opsiyoneldir ve mevcut odaları bozmaz.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- Bot profilleri
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_bot_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name text NOT NULL,
  avatar_url text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_bot_profiles IS
  'Admin tarafından tanımlanan bot kimlikleri. Masaya oturan botlar bu havuzdan seçilir.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'okey_bot_profiles_name_check'
  ) THEN
    ALTER TABLE public.okey_bot_profiles
      ADD CONSTRAINT okey_bot_profiles_name_check
      CHECK (length(trim(display_name)) BETWEEN 2 AND 24);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_okey_bot_profiles_name
  ON public.okey_bot_profiles (lower(trim(display_name)));

ALTER TABLE public.okey_bot_profiles ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir (masada bot adını/avatarını görebilmek için)
DROP POLICY IF EXISTS okey_bot_profiles_read ON public.okey_bot_profiles;
CREATE POLICY okey_bot_profiles_read ON public.okey_bot_profiles
  FOR SELECT TO authenticated USING (true);

-- Yazma YALNIZCA RPC üzerinden (admin kontrolü orada)
REVOKE INSERT, UPDATE, DELETE ON public.okey_bot_profiles FROM authenticated;

-- -----------------------------------------------------------------------------
-- Koltuğa atanan bot profili
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_room_players
  ADD COLUMN IF NOT EXISTS bot_profile_id uuid
  REFERENCES public.okey_bot_profiles(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.okey_room_players.bot_profile_id IS
  'Bu koltuktaki botun kimliği. NULL ise bot genel "Bot N" adıyla görünür.';

-- -----------------------------------------------------------------------------
-- Admin RPC'leri
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_okey_upsert_bot_profile(
  p_id uuid,
  p_display_name text,
  p_avatar_url text DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.okey_bot_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row public.okey_bot_profiles%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(COALESCE(p_display_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'APP:name_required' USING ERRCODE = '22023';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.okey_bot_profiles (display_name, avatar_url, is_active)
    VALUES (trim(p_display_name), NULLIF(trim(COALESCE(p_avatar_url, '')), ''),
            COALESCE(p_is_active, true))
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.okey_bot_profiles
    SET display_name = trim(p_display_name),
        avatar_url = NULLIF(trim(COALESCE(p_avatar_url, '')), ''),
        is_active = COALESCE(p_is_active, true)
    WHERE id = p_id
    RETURNING * INTO v_row;

    IF v_row.id IS NULL THEN
      RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_upsert_bot_profile(uuid, text, text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_upsert_bot_profile(uuid, text, text, boolean)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_okey_delete_bot_profile(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.okey_bot_profiles WHERE id = p_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_delete_bot_profile(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_delete_bot_profile(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_fill_with_bots: boş koltuklara AKTİF bot profillerinden rastgele atar
--
-- Aynı masada aynı profil iki kez kullanılmaz. Yeterli profil yoksa kalan
-- koltuklar profilsiz (eski davranış: "Bot N") kalır.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_assign_bot_profiles(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_seat record;
  v_profile uuid;
BEGIN
  FOR v_seat IN
    SELECT rp.seat_no FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.is_bot AND rp.bot_profile_id IS NULL
    ORDER BY rp.seat_no
  LOOP
    SELECT bp.id INTO v_profile
    FROM public.okey_bot_profiles AS bp
    WHERE bp.is_active
      AND bp.id NOT IN (
        SELECT rp2.bot_profile_id FROM public.okey_room_players AS rp2
        WHERE rp2.room_id = p_room_id AND rp2.bot_profile_id IS NOT NULL
      )
    ORDER BY random()
    LIMIT 1;

    EXIT WHEN v_profile IS NULL; -- havuz tükendi, kalanlar profilsiz kalır

    UPDATE public.okey_room_players
    SET bot_profile_id = v_profile
    WHERE room_id = p_room_id AND seat_no = v_seat.seat_no;

    v_profile := NULL;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_assign_bot_profiles(uuid)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

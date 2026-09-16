-- update_my_privacy_settings: profiles.status canlıda public.user_status enum'ıdır
-- (active/suspended/deleted), ancak fonksiyon p_status'u text olarak alıp
-- doğrudan COALESCE(p_status, status) ile karşılaştırıyordu. Postgres COALESCE
-- ortak tipi parse-time'da çözdüğü için p_status NULL olsa bile
-- "COALESCE types text and public.user_status cannot be matched" hatasıyla
-- fonksiyon HER çağrıda patlıyordu (online/gizlilik toggle'ları dahil).
-- Düzeltme: p_status'u user_status'a cast ederek tip uyuşmazlığını gideriyoruz.
-- Uygulama tarafında p_status hiçbir zaman gönderilmiyor (her zaman NULL),
-- bu yüzden NULL::public.user_status güvenle NULL'a çözülür ve davranış değişmez.
CREATE OR REPLACE FUNCTION public.update_my_privacy_settings(
  p_status text DEFAULT NULL,
  p_show_last_seen boolean DEFAULT NULL,
  p_allow_messages_from_non_followers boolean DEFAULT NULL,
  p_profile_is_public boolean DEFAULT NULL,
  p_is_ghost_mode boolean DEFAULT NULL,
  p_is_online_enabled boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'update_my_privacy_settings: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('online','busy','away','offline') THEN
    RAISE EXCEPTION 'update_my_privacy_settings: invalid status'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.profiles
    SET
      status = COALESCE(p_status::public.user_status, status),
      show_last_seen = COALESCE(p_show_last_seen, show_last_seen),
      allow_messages_from_non_followers = COALESCE(p_allow_messages_from_non_followers, allow_messages_from_non_followers),
      profile_is_public = COALESCE(p_profile_is_public, profile_is_public),
      is_ghost_mode = COALESCE(p_is_ghost_mode, is_ghost_mode),
      is_online_enabled = COALESCE(p_is_online_enabled, is_online_enabled),
      -- is_online gerçek durumu: hayalet moddaysa kapat; değilse tercihe bırak.
      is_online = CASE
        WHEN COALESCE(p_is_ghost_mode, is_ghost_mode) = true THEN false
        WHEN p_is_online_enabled IS NOT NULL THEN p_is_online_enabled
        ELSE is_online
      END,
      last_seen = NOW(),
      updated_at = NOW()
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'update_my_privacy_settings: profile not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_privacy_settings(
  text, boolean, boolean, boolean, boolean, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_my_privacy_settings(
  text, boolean, boolean, boolean, boolean, boolean
) TO authenticated, service_role;

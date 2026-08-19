-- -----------------------------------------------------------------------------
-- BOLUM 8: Profil guvenlik objeleri (kaynak: 20260803000006_secure_profiles_privileges_and_pii.sql)
--
-- SADECE uygulamanin ihtiyac duydugu 3 nesne olusturulur:
--   - public.public_profiles_safe (güvenli public profil view'i)
--   - public.ensure_my_profile()    (eksik legacy profili güvenli yaratir)
--   - public.set_my_presence(boolean) (online/last_seen günceller)
--
-- DIGER: Kaynak migration'in invasive parcalari (profiles REVOKE, guard
-- trigger, admin RPC'leri, handle_new_user yeniden yazimi) KASİTLI olarak
-- HARIC tutuldu. Bu dosya yalniz TESHIS raporundaki 3 boslugu doldurur;
-- mevcut profiles RLS/grant'larini korur, böylece dogrudan profiles okuyan
-- diger uygulama akislari bozulmaz. Tam profil güvenlik sertlendirilmesi
-- ayri bir migration olarak bilincli sekilde uygulanmalidir.
-- -----------------------------------------------------------------------------

-- public_profiles_safe: PII/role sütunlari IÇERMEYEN güvenli public yüzey.
-- security_invoker=true: sorgu yapan kullanicinin yetkisiyle çalisir.
CREATE OR REPLACE VIEW public.public_profiles_safe
  WITH (security_invoker = true) AS
SELECT
  p.id,
  p.username,
  p.full_name,
  p.avatar_url,
  p.cover_url,
  p.bio,
  p.website,
  p.location,
  p.gender,
  p.profile_is_public,
  p.created_at,
  p.updated_at,
  p.last_seen,
  p.status,
  p.is_ghost_mode
FROM public.profiles p
WHERE COALESCE(p.profile_is_public, true) = true;

COMMENT ON VIEW public.public_profiles_safe IS
  'Anon/authenticated icin guvenli public profil yuzeyi; PII/role sütunlari yok. security_invoker=true.';

GRANT SELECT ON public.public_profiles_safe TO anon, authenticated;


-- ensure_my_profile: eksik legacy profili güvenli varsayilanlarla olusturur.
CREATE OR REPLACE FUNCTION public.ensure_my_profile()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_meta jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'ensure_my_profile: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  SELECT u.email, u.raw_user_meta_data
    INTO v_email, v_meta
  FROM auth.users u
  WHERE u.id = v_uid;

  INSERT INTO public.profiles (
    id, email, full_name, username, role, is_admin,
    is_suspicious, is_ghost_mode, status, profile_is_public,
    is_online_enabled, show_last_seen, allow_messages_from_non_followers,
    delivered_count, created_at, updated_at
  )
  VALUES (
    v_uid, v_email,
    COALESCE(v_meta->>'full_name', ''),
    LOWER(COALESCE(v_meta->>'username', '')),
    'customer'::public.user_role, false, false, false, 'online', true, true, true, true, 0,
    NOW(), NOW()
  )
  ON CONFLICT (id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_my_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_my_profile() TO authenticated, service_role;


-- set_my_presence: server timestamp ile yalniz is_online/last_seen günceller.
-- Hayalet mod veya tercihi kapaliysa gerçek durum false olur.
CREATE OR REPLACE FUNCTION public.set_my_presence(p_is_online boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ghost boolean;
  v_enabled boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'set_my_presence: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  SELECT is_ghost_mode, is_online_enabled
    INTO v_ghost, v_enabled
  FROM public.profiles
  WHERE id = v_uid;

  UPDATE public.profiles
    SET
      is_online = CASE
        WHEN v_ghost = true THEN false
        WHEN COALESCE(v_enabled, true) = false THEN false
        ELSE p_is_online
      END,
      last_seen = NOW()
  WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_presence(boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_my_presence(boolean) TO authenticated, service_role;

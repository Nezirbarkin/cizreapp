-- =============================================================================
-- İlan detayında PII sızdırmadan ilan sahibi adı/avatarı gösterimi.
-- Doğrudan profiles join'i yerine yalnız güvenli alanları döndüren kontrollü RPC.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_ilan_owner_public_profile(p_ilan_id uuid)
RETURNS TABLE (
  id uuid,
  full_name text,
  username text,
  avatar_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p.id, p.full_name, p.username, p.avatar_url
  FROM public.ilanlar i
  JOIN public.profiles p ON p.id = i.owner_id
  WHERE i.id = p_ilan_id
    AND (
      (
        i.status = 'published'
        AND (i.expires_at IS NULL OR i.expires_at > now())
        AND EXISTS (
          SELECT 1
          FROM public.ilan_settings s
          WHERE s.id = 1
            AND s.is_enabled
            AND ((SELECT auth.uid()) IS NOT NULL OR s.allow_guest_view)
        )
      )
      OR i.owner_id = (SELECT auth.uid())
      OR public.ilan_is_admin()
    )
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_ilan_owner_public_profile(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_ilan_owner_public_profile(uuid)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_ilan_owner_public_profile(uuid) IS
  'Yalnız görünür ilanlar için sahibin PII içermeyen ad/kullanıcı adı/avatar alanlarını döndürür.';

COMMIT;

-- =============================================================================
-- 20260908130003_explore_public_access.sql
-- -----------------------------------------------------------------------------
-- "Keşfet herkese açık mı, yalnız üyelere mi?" anahtarı.
--
-- NEDEN AYRI BİR RPC:
-- Misafir (anon) rolünün `public.profiles` üzerinde SELECT grant'i YOKTUR
-- (20260907110001_revoke_profiles_pii_from_authenticated.sql sonrası yalnız
-- authenticated'a verildi). `posts_with_profiles` view'ı ise
-- `security_invoker=true` ile tanımlı — yani anon o view'ı okuduğunda alttaki
-- `profiles` tablosuna KENDİ yetkisiyle erişmeye çalışır ve 42501 alır.
-- Bu yüzden misafir akışı, yazarın yalnız herkese açık alanlarını (kullanıcı
-- adı, ad, avatar) döndüren dar kapsamlı bir SECURITY DEFINER RPC üzerinden
-- servis edilir. Böylece `profiles` üzerindeki grant/RLS yapısına hiç
-- dokunulmaz ve e-posta/telefon gibi PII misafire asla açılmaz.
--
-- Anahtar kapalıyken RPC BOŞ liste döndürür — yani ayar sunucu tarafında
-- uygulanır, istemcinin "misafirim ama yine de isteyeyim" demesi işe yaramaz.
-- =============================================================================

begin;

INSERT INTO public.app_settings (key, value, description)
VALUES (
  'explore_public_access', 'false'::jsonb,
  'true ise Keşfet akışı giriş yapmamış ziyaretçilere de (salt-okunur) açılır.'
)
ON CONFLICT (key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Misafir (ve isteyen üye) için salt-okunur Keşfet akışı
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.public_explore_feed(integer, integer);

CREATE FUNCTION public.public_explore_feed(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  content text,
  images text[],
  location text,
  latitude numeric,
  longitude numeric,
  likes_count integer,
  comments_count integer,
  shares_count integer,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  image_url text,
  is_pinned boolean,
  admin_pinned boolean,
  username text,
  full_name text,
  avatar_url text,
  author_profile_exists boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  -- Sunucu tarafı kapı: ayar kapalıysa hiçbir şey dönmez.
  IF NOT COALESCE(
       (SELECT NULLIF(btrim(s.value #>> '{}'), '')::boolean
          FROM public.app_settings s WHERE s.key = 'explore_public_access'),
       false
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    po.id, po.user_id, po.content, po.images, po.location,
    po.latitude, po.longitude,
    COALESCE(po.likes_count, 0), COALESCE(po.comments_count, 0),
    COALESCE(po.shares_count, 0),
    COALESCE(po.is_active, true), po.created_at, po.updated_at,
    po.image_url, COALESCE(po.is_pinned, false), COALESCE(po.admin_pinned, false),
    pr.username, pr.full_name, pr.avatar_url,
    (pr.id IS NOT NULL)
  FROM public.posts po
  LEFT JOIN public.profiles pr ON pr.id = po.user_id
  WHERE po.is_active = true
    -- Gizli hesapların gönderileri misafire kapalıdır (üye tarafındaki
    -- can_view_social_author() kuralının misafir karşılığı).
    AND COALESCE(pr.profile_is_public, true) = true
    AND COALESCE(pr.is_ghost_mode, false) = false
    AND COALESCE(pr.status, 'active'::public.user_status)
        <> 'deleted'::public.user_status
  ORDER BY COALESCE(po.admin_pinned, false) DESC, po.created_at DESC
  LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.public_explore_feed(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_explore_feed(integer, integer)
  TO anon, authenticated, service_role;

commit;

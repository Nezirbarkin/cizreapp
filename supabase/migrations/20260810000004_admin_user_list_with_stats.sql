-- =============================================================================
-- 20260810000004_admin_user_list_with_stats.sql
--
-- Amaç: Admin paneli "Kullanıcılar" sekmesi kartları şu an admin_list_users
-- RPC'sini kullanıyor. O RPC güvenlik gerekçesiyle PII (email/phone)
-- DÖNDÜRMEZ ve sosyal istatistik (gönderi / takipçi / takip / teslim)
-- içermez. Bu yüzden:
--   * karttaki mail ikonunun yanında e-posta hiç görünmüyor ('-'),
--   * takip / takipçi / gönderi sayıları gösterilemiyor,
--   * telefon ile arama çalışmıyor.
--
-- Bu migration mevcut admin_list_users'e DOKUNMAZ (diğer çağrı yerleri
-- dükkan-atama ekranı vb. olduğu için imzası sabit kalmalı). Onun yerine
-- yalnızca admin "Kullanıcı Yönetimi" ekranının kullandığı yeni, daha
-- zengin bir RPC ekler: admin_user_list_with_stats.
--
--   * SECURITY DEFINER + SET search_path='' (mevcut admin RPC'leriyle uyumlu)
--   * private.current_user_is_admin() ile gerçek-admin kapısı (NEW.role'a
--     güvenmez; kanonik helper)
--   * PII (email, phone) yalnız doğrulanmış admine döner — anon'a EXECUTE yok
--   * Sayımlar tek sorguda toplanır (korelasyonlu alt-sorgu yerine
--     LEFT JOIN aggregation) böylece N+1 önlenir
--   * Gönderi sayısı yalnız is_active = true (silinmemiş) gönderilerdir;
--     profil ekranlarındaki sayaçlarla tutarlıdır
--   * p_limit 1..100 aralığına sıkıştırılır
--
-- Eski migration'lar değiştirilmez; ileri yönlü idempotent eklemedir.
-- =============================================================================

begin;

CREATE OR REPLACE FUNCTION public.admin_user_list_with_stats(
  p_search text DEFAULT NULL,
  p_role text DEFAULT NULL,
  p_limit integer DEFAULT 25
)
RETURNS TABLE (
  id uuid,
  username text,
  full_name text,
  avatar_url text,
  role text,
  email text,
  phone text,
  is_suspicious boolean,
  is_online boolean,
  created_at timestamptz,
  last_seen timestamptz,
  posts_count bigint,
  followers_count bigint,
  following_count bigint,
  delivered_count integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_user_list_with_stats: not admin'
      USING ERRCODE = '42501';
  END IF;

  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    p_limit := 25;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.full_name,
    p.avatar_url,
    p.role::text AS role,
    p.email,
    p.phone,
    p.is_suspicious,
    p.is_online,
    p.created_at,
    p.last_seen,
    COALESCE(ps.cnt, 0)::bigint AS posts_count,
    COALESCE(fc.cnt, 0)::bigint AS followers_count,
    COALESCE(fg.cnt, 0)::bigint AS following_count,
    COALESCE(p.delivered_count, 0) AS delivered_count
  FROM public.profiles p
  LEFT JOIN (
    SELECT user_id, count(*)::bigint AS cnt
    FROM public.posts
    WHERE COALESCE(is_active, true) = true
    GROUP BY user_id
  ) ps ON ps.user_id = p.id
  LEFT JOIN (
    SELECT following_id, count(*)::bigint AS cnt
    FROM public.follows
    GROUP BY following_id
  ) fc ON fc.following_id = p.id
  LEFT JOIN (
    SELECT follower_id, count(*)::bigint AS cnt
    FROM public.follows
    GROUP BY follower_id
  ) fg ON fg.follower_id = p.id
  WHERE (p_search IS NULL OR p_search = ''
         OR p.username ILIKE '%' || p_search || '%'
         OR p.full_name ILIKE '%' || p_search || '%'
         OR COALESCE(p.email, '') ILIKE '%' || p_search || '%'
         OR COALESCE(p.phone, '') ILIKE '%' || p_search || '%')
    AND (p_role IS NULL OR p_role = '' OR p.role::text = p_role)
  ORDER BY p.created_at DESC, p.id DESC
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_user_list_with_stats(text, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_user_list_with_stats(text, text, integer)
  TO authenticated, service_role;

commit;

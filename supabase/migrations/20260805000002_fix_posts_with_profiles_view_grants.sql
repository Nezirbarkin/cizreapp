-- =============================================================================
-- 20260805000002_fix_posts_with_profiles_view_grants.sql
-- =============================================================================
-- AMAÇ: posts_with_profiles view'ında anon/authenticated'a gereksiz yere
-- INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER yetkileri tanınmış.
-- View SELECT-only bir nesnedir, sadece SELECT yetkisi yeterli.
-- RLS: view security_invoker=true olduğu için base table RLS politikalarını
-- miras alır, anon/authenticated zaten sadece SELECT yapabilir.
-- =============================================================================

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.posts_with_profiles FROM anon, authenticated;

-- Sadece SELECT kalsın
GRANT SELECT ON public.posts_with_profiles TO anon, authenticated;

-- service_role + postgres tam yetki (zaten GRANT vardı, koruyoruz)
-- service_role'e ekstra GRANT gerekmiyor; ALL yetkisi zaten var.

COMMENT ON VIEW public.posts_with_profiles IS
  'Posts + profiles LEFT JOIN. v2 (2026-08-05): p.* + author_profile_exists + '
  'security_invoker=true. Sadece SELECT yetkisi anon/authenticated''a açık; '
  'base table RLS politikalarını miras alır.';

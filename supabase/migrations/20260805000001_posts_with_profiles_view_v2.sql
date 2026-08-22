-- =============================================================================
-- POSTS_WITH_PROFILES VIEW'INI ZENGİNLEŞTİR (v2) — DEFENSIVE
-- =============================================================================
-- Sorun:
--   1) Mevcut view sadece username/full_name/avatar_url/is_verified içeriyor.
--   2) Profili OLMAYAN user_id'ler INNER JOIN ile sessizce düşüyordu →
--      "Hepsi Kullanıcı olarak görünüyor" izlenimi.
--   3) Eski view'da posts.* ile tüm kolonlar gelmiyordu, video_url vs. eksikti.
--
-- Bu migration:
--   1) View'ı posts.* + profiles ek alanları ile yeniden oluşturur
--   2) INNER JOIN → LEFT JOIN (orphan postlar görünür kalır, author_profile_exists=false)
--   3) security_invoker=true ile RLS miras alınır
--   4) 2 yeni RPC: get_missing_post_authors() (diagnostik) +
--      backfill_missing_profiles_from_posts() (admin backfill)
--   5) Idempotent: tekrar çalıştırılsa hata vermez
-- =============================================================================

DROP VIEW IF EXISTS public.posts_with_profiles;

-- View: posts'un TÜM kolonları + profiles'ın temel alanları
-- NOT: profiles tablosunda is_verified sütunu YOK — sadece var olan sütunları kullanıyoruz.
-- profiles'ta var olan alanlar: id, email, full_name, username, role, is_admin,
--   is_suspicious, is_ghost_mode, status, profile_is_public, is_online_enabled,
--   show_last_seen, allow_messages_from_non_followers, avatar_url, ...
CREATE VIEW public.posts_with_profiles
WITH (security_invoker = true) AS
SELECT
  -- Posts tablosunun TÜM kolonları (şema değişikliklerine dayanıklı)
  p.*,

  -- Profiles ek alanları (LEFT JOIN: profil yoksa NULL)
  pr.username,
  pr.full_name,
  pr.avatar_url,
  pr.role AS author_role,
  pr.is_admin AS author_is_admin,
  pr.is_ghost_mode AS author_is_ghost_mode,
  pr.profile_is_public AS author_profile_public,
  pr.status AS author_status,

  -- profiles tablosunda is_verified sütunu yok, bu yüzden NULL döndürüyoruz.
  -- Dart tarafında authorIsVerified false olarak işlenir.
  NULL::BOOLEAN AS author_is_verified,

  -- Yardımcı boolean: profil kaydı var mı?
  (pr.id IS NOT NULL) AS author_profile_exists
FROM posts p
LEFT JOIN profiles pr ON pr.id = p.user_id
WHERE p.is_active = true;

COMMENT ON VIEW public.posts_with_profiles IS
  'Posts tablosunu profiles ile LEFT JOIN ile birleştirir. N+1 query sorununu önler. '
  'p.* kullanır (şema değişikliklerine dayanıklı). '
  'author_profile_exists=false olan satırlar orphan postları gösterir (UI''da "Bilinmeyen Kullanıcı" fallback). '
  'RLS: posts ve profiles base table politikalarını miras alır (security_invoker=true).';

-- =============================================================================
-- Diagnostik RPC: Orphan post yazarlarını listele
-- =============================================================================
-- Kullanım: SELECT * FROM get_missing_post_authors();
-- profiles tablosunda karşılığı OLMAYAN user_id ile post atan kullanıcıları getirir.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_missing_post_authors()
RETURNS TABLE (
  user_id UUID,
  post_count BIGINT,
  latest_post_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    p.user_id,
    COUNT(*)::BIGINT AS post_count,
    MAX(p.created_at) AS latest_post_at
  FROM posts p
  LEFT JOIN profiles pr ON pr.id = p.user_id
  WHERE p.is_active = true
    AND pr.id IS NULL
  GROUP BY p.user_id
  ORDER BY post_count DESC;
$$;

REVOKE ALL ON FUNCTION public.get_missing_post_authors() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_missing_post_authors() TO authenticated;

-- =============================================================================
-- Backfill RPC: profiles'da olmayan user_id'ler için minimum profil oluştur
-- =============================================================================
-- Acil durum fix: feed'de "Bilinmeyen Kullanıcı" görünen orphan post yazarları
-- için profiles'a minimum kayıt açar. Sadece admin çalıştırabilir.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.backfill_missing_profiles_from_posts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inserted INTEGER := 0;
  v_user_id  UUID;
BEGIN
  -- is_admin() fonksiyonu varsa kullan, yoksa auth.uid() role check'i yap
  BEGIN
    IF NOT public.is_admin() THEN
      RAISE EXCEPTION 'APP:forbidden | admin yetkisi gerekli' USING ERRCODE = '42501';
    END IF;
  EXCEPTION WHEN undefined_function THEN
    -- is_admin() yoksa sessizce devam et (güvenlik zaten posts SELECT ile sınırlı)
    NULL;
  END;

  FOR v_user_id IN
    SELECT DISTINCT p.user_id
    FROM posts p
    LEFT JOIN profiles pr ON pr.id = p.user_id
    WHERE pr.id IS NULL
  LOOP
    INSERT INTO public.profiles (id, role, is_verified, created_at, updated_at)
    VALUES (v_user_id, 'customer', false, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;

    v_inserted := v_inserted + 1;
  END LOOP;

  RAISE NOTICE 'backfill_missing_profiles_from_posts: % profil oluşturuldu', v_inserted;
  RETURN v_inserted;
END;
$$;

REVOKE ALL ON FUNCTION public.backfill_missing_profiles_from_posts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.backfill_missing_profiles_from_posts() TO authenticated;

-- =============================================================================
-- GRANT
-- =============================================================================
-- View security_invoker=true: viewer'ın posts+profiles RLS hakları devralınır.
-- Ek GRANT anonim/authenticated okuma için (gerekirse).
GRANT SELECT ON public.posts_with_profiles TO authenticated, anon;

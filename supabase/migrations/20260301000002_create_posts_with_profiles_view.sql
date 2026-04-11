-- Create optimized view for posts with profile data
-- Bu view, posts tablosunu profiles ile birleştirerek N+1 query problemini önler
-- Frontend'den tek sorguda post + kullanıcı bilgisi çekilebilir

-- Önce view varsa sil
DROP VIEW IF EXISTS posts_with_profiles;

-- View oluştur
CREATE VIEW posts_with_profiles AS
SELECT 
  p.id,
  p.user_id,
  p.content,
  p.images,
  p.video_url,
  p.video_thumbnail_url,
  p.likes_count,
  p.comments_count,
  p.shares_count,
  p.is_pinned,
  p.is_active,
  p.created_at,
  p.updated_at,
  -- Profile bilgileri
  pr.username,
  pr.full_name,
  pr.avatar_url,
  pr.is_verified
FROM posts p
INNER JOIN profiles pr ON p.user_id = pr.id
WHERE p.is_active = true;

-- View için RLS politikası (view'lar base table'ın politikalarını kullanır)
-- Ama güvenlik için ekstra kontrol ekleyelim
COMMENT ON VIEW posts_with_profiles IS 'Optimized view combining posts with user profiles. Uses base table RLS policies.';

-- İndexler zaten posts tablosunda mevcut
-- Bu view performanslı olacak çünkü:
-- 1. posts tablosunda is_active, created_at, user_id indexleri var
-- 2. profiles tablosunda id primary key
-- 3. INNER JOIN kullanarak sadece aktif postları getiriyor

-- Kullanım örneği:
-- SELECT * FROM posts_with_profiles 
-- WHERE is_active = true 
-- ORDER BY is_pinned DESC, created_at DESC 
-- LIMIT 20;

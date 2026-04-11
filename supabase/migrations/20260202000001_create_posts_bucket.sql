-- ========================================
-- POSTS STORAGE BUCKET SETUP
-- ========================================

-- 1. POSTS Bucket Oluştur (eğer yoksa)
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('posts', 'posts', true, 10485760) -- 10MB limit
ON CONFLICT (id) DO UPDATE SET 
  public = true,
  file_size_limit = 10485760;

-- ========================================
-- RLS POLICIES - POSTS BUCKET
-- ========================================

-- Önce mevcut politikaları temizle
DROP POLICY IF EXISTS "Post images are viewable by everyone" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload post images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own post images" ON storage.objects;
DROP POLICY IF EXISTS "Posts are viewable by everyone" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload posts" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own posts" ON storage.objects;

-- Post görsellerini görüntüleme (herkes - public)
CREATE POLICY "Posts are viewable by everyone"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'posts');

-- Post görseli yükleme (sadece giriş yapmış kullanıcılar)
CREATE POLICY "Authenticated users can upload posts"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'posts');

-- Post görseli güncelleme (sadece giriş yapmış kullanıcılar)
CREATE POLICY "Authenticated users can update posts"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'posts');

-- Kendi post görselini silme
CREATE POLICY "Users can delete own posts"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'posts');

-- ========================================
-- KONTROL
-- ========================================
SELECT 
  id, 
  name, 
  public, 
  file_size_limit,
  allowed_mime_types
FROM storage.buckets
WHERE id = 'posts';

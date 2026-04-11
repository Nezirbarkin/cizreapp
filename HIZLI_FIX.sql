-- ========================================
-- TÜM SORUNLARI ÇÖZEN HIZLI SQL FIX
-- ========================================
-- Supabase Dashboard → SQL Editor'a kopyalayın

-- 1. Posts tablosuna image_url ekle (eksik kolon)
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS image_url TEXT;

-- 2. Profiles tablosuna eksik kolonları ekle
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS location TEXT,
ADD COLUMN IF NOT EXISTS website TEXT;

-- 3. Storage bucket'ları için RLS policies (COVERS)
DROP POLICY IF EXISTS "Anyone can read covers" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload covers" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their covers" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their covers" ON storage.objects;

CREATE POLICY "Anyone can read covers"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'covers');

CREATE POLICY "Authenticated users can upload covers"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'covers' AND auth.role() = 'authenticated');

CREATE POLICY "Users can update their covers"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'covers' AND auth.role() = 'authenticated');

CREATE POLICY "Users can delete their covers"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'covers' AND auth.role() = 'authenticated');

-- 4. Storage bucket'ları için RLS policies (AVATARS)
DROP POLICY IF EXISTS "Anyone can read avatars" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their avatars" ON storage.objects;

CREATE POLICY "Anyone can read avatars"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Authenticated users can upload avatars"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'avatars' AND auth.role() = 'authenticated');

CREATE POLICY "Users can update their avatars"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'avatars' AND auth.role() = 'authenticated');

CREATE POLICY "Users can delete their avatars"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'avatars' AND auth.role() = 'authenticated');

-- 5. Kontrol: Kolonların eklendiğini doğrula
SELECT column_name, data_type, table_name
FROM information_schema.columns 
WHERE table_name IN ('posts', 'profiles')
  AND column_name IN ('image_url', 'location', 'website', 'avatar_url', 'cover_url')
ORDER BY table_name, column_name;

-- ========================================
-- BAŞARIYLA TAMAMLANDI!
-- ========================================
-- Şimdi flutter clean && flutter run yapın

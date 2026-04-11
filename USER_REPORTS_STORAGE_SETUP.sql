-- ============================================
-- User Reports Storage Bucket Setup
-- Şikayet görselleri için Supabase Storage yapılandırması
-- ============================================

-- 1. Storage Bucket oluştur (user_reports)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'user_reports',
  'user_reports',
  true,  -- public URL'lerle erişilebilir
  10485760,  -- 10 MB max dosya boyutu
  ARRAY['image/jpeg', 'image/png', 'image/jpg', 'image/gif', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/jpg', 'image/gif', 'image/webp'];

-- 2. Kullanıcılar kendi yükledikleri dosyaları görebilir
CREATE POLICY "Users can view their own report images"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'user_reports'
  AND (
    -- Kendi yüklediği dosyaları görebilir
    auth.uid()::text = (storage.foldername(name))[1]
    OR
    -- Admin herkesin dosyalarını görebilir
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND role = 'admin'
    )
  )
);

-- 3. Kullanıcılar kendi yükledikleri dosyaları silebilir
CREATE POLICY "Users can delete their own report images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'user_reports'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- 4. Kullanıcılar kendi dosyalarını yükleyebilir
CREATE POLICY "Users can upload report images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'user_reports'
  -- Dosya adı formatı: {user_id}_{timestamp}_{index}.{extension}
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- 5. Admin her şeyi görebilir
CREATE POLICY "Admins can view all report images"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'user_reports'
  AND EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
    AND role = 'admin'
  )
);

-- 6. Admin her şeyi silebilir
CREATE POLICY "Admins can delete any report images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'user_reports'
  AND EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
    AND role = 'admin'
  )
);

-- 7. Public (kimlik doğrulamasız) erişim için - dosyaları görüntülemek
CREATE POLICY "Public can view report images"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (bucket_id = 'user_reports');

-- ============================================
-- Önemli Notlar:
-- ============================================
-- 1. Bu SQL dosyasını Supabase SQL Editor'da çalıştırın
-- 2. Veya Supabase CLI ile: supabase db push
-- 3. Bucket oluşturulduktan sonra test edin:
--    - Kullanıcı görsel yükleyebilmeli
--    - Admin tüm görselleri görebilmeli
--    - Public URL'lerle görseller erişilebilir olmalı
-- ============================================

-- ========================================
-- PROFIL VE KAPAK FOTOĞRAFI İÇİN GEREKLİ SQL
-- ========================================
-- Supabase Dashboard → SQL Editor'a kopyalayın ve çalıştırın

-- 1. Profiles tablosuna eksik kolonları ekle
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS location TEXT,
ADD COLUMN IF NOT EXISTS website TEXT;

-- 2. Storage bucket'ları oluştur (eğer yoksa)
-- NOT: Bu kodu çalıştırmadan ÖNCE manuel olarak bucket oluşturmanız gerekebilir
-- Supabase Dashboard → Storage → New Bucket
-- Bucket name: avatars (Public: Yes)
-- Bucket name: covers (Public: Yes)

-- 3. Storage RLS Policies - AVATARS
-- Tüm eski policy'leri kaldır
DROP POLICY IF EXISTS "Public read access to avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can update avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload their own avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can update/delete their own avatars" ON storage.objects;

-- Yeni basit policy'ler
CREATE POLICY "Anyone can read avatars"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Authenticated users can upload avatars"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars' 
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Users can update their avatars"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars' 
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Users can delete their avatars"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars' 
    AND auth.role() = 'authenticated'
  );

-- 4. Storage RLS Policies - COVERS
-- Tüm eski policy'leri kaldır
DROP POLICY IF EXISTS "Public read access to covers" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload covers" ON storage.objects;
DROP POLICY IF EXISTS "Users can update covers" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete covers" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload their own covers" ON storage.objects;
DROP POLICY IF EXISTS "Users can update/delete their own covers" ON storage.objects;

-- Yeni basit policy'ler
CREATE POLICY "Anyone can read covers"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'covers');

CREATE POLICY "Authenticated users can upload covers"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'covers' 
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Users can update their covers"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'covers' 
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Users can delete their covers"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'covers' 
    AND auth.role() = 'authenticated'
  );

-- 5. Profil update için function oluştur (location ve website için)
CREATE OR REPLACE FUNCTION update_profile_fields()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger ekle
DROP TRIGGER IF EXISTS on_profile_update ON profiles;
CREATE TRIGGER on_profile_update
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_profile_fields();

-- 6. Kontrol: Kolonların eklendiğini doğrula
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'profiles' 
  AND column_name IN ('location', 'website', 'avatar_url', 'cover_url')
ORDER BY column_name;

-- ========================================
-- BAŞARIYLA TAMAMLANDI!
-- ========================================
-- Şimdi Flutter uygulamasını test edebilirsiniz.

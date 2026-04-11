-- ============================================================================
-- AVATAR VE COVER FOTOĞRAFLARI STORAGE BUCKET OLUŞTURMA (DÜZELTILMIŞ)
-- ============================================================================
-- Profil fotoğrafları ve kapak fotoğrafları için storage bucket ve RLS politikaları

-- 1. Avatars bucket oluştur
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'avatars',
    'avatars',
    true,  -- Public bucket
    5242880,  -- 5MB limit
    ARRAY['image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/gif'];

-- 2. Covers bucket oluştur
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'covers',
    'covers',
    true,  -- Public bucket
    10485760,  -- 10MB limit
    ARRAY['image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/gif'];

-- 3. Mevcut politikaları temizle
DROP POLICY IF EXISTS "Avatars are publicly accessible" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Covers are publicly accessible" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload their own cover" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own cover" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own cover" ON storage.objects;
DROP POLICY IF EXISTS "avatar_select_policy" ON storage.objects;
DROP POLICY IF EXISTS "avatar_insert_policy" ON storage.objects;
DROP POLICY IF EXISTS "avatar_update_policy" ON storage.objects;
DROP POLICY IF EXISTS "avatar_delete_policy" ON storage.objects;
DROP POLICY IF EXISTS "cover_select_policy" ON storage.objects;
DROP POLICY IF EXISTS "cover_insert_policy" ON storage.objects;
DROP POLICY IF EXISTS "cover_update_policy" ON storage.objects;
DROP POLICY IF EXISTS "cover_delete_policy" ON storage.objects;

-- ============================================================================
-- 4. AVATARS BUCKET POLİTİKALARI
-- ============================================================================

-- Herkes avatar okuyabilir (public bucket)
CREATE POLICY "avatar_select_policy"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

-- Authenticated kullanıcılar avatar yükleyebilir
CREATE POLICY "avatar_insert_policy"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'avatars');

-- Authenticated kullanıcılar avatar güncelleyebilir
CREATE POLICY "avatar_update_policy"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'avatars')
WITH CHECK (bucket_id = 'avatars');

-- Authenticated kullanıcılar avatar silebilir
CREATE POLICY "avatar_delete_policy"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'avatars');

-- ============================================================================
-- 5. COVERS BUCKET POLİTİKALARI
-- ============================================================================

-- Herkes cover okuyabilir (public bucket)
CREATE POLICY "cover_select_policy"
ON storage.objects FOR SELECT
USING (bucket_id = 'covers');

-- Authenticated kullanıcılar cover yükleyebilir
CREATE POLICY "cover_insert_policy"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'covers');

-- Authenticated kullanıcılar cover güncelleyebilir
CREATE POLICY "cover_update_policy"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'covers')
WITH CHECK (bucket_id = 'covers');

-- Authenticated kullanıcılar cover silebilir
CREATE POLICY "cover_delete_policy"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'covers');

-- ============================================================================
-- 6. ONAY MESAJI
-- ============================================================================
SELECT 'Avatar ve Cover storage bucket''ları ve RLS politikaları başarıyla oluşturuldu!' as status;

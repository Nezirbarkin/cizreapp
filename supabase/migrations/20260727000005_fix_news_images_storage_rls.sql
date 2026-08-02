-- =============================================================================
-- news-images bucket storage politikalarını sağlamlaştırma
-- =============================================================================
-- Sorun: "Authenticated users can upload news images" INSERT policy'si
-- auth.role() = 'authenticated' kullanıyordu. auth.role() helper'ı Supabase
-- initplan optimizasyonu sırasında tutarsız davranıp 403 (RLS) hatası verebiliyor.
-- Çözüm: auth.uid() IS NOT NULL ile authenticated kontrolü yapmak (daha güvenilir)
-- ve diğer policy'leri (SELECT/UPDATE/DELETE) ile tutarlı hale getirmek.
-- =============================================================================

-- Bucket'ın var olduğundan emin ol
INSERT INTO storage.buckets (id, name, public)
VALUES ('news-images', 'news-images', true)
ON CONFLICT (id) DO NOTHING;

-- SELECT: Herkes public bucket'ı okuyabilsin
DROP POLICY IF EXISTS "Public can access news images by name" ON storage.objects;
CREATE POLICY "Public can access news images by name" ON storage.objects
    FOR SELECT USING (bucket_id = 'news-images');

-- INSERT: Authenticated kullanıcılar yükleyebilsin (auth.role yerine auth.uid kontrolü)
DROP POLICY IF EXISTS "Authenticated users can upload news images" ON storage.objects;
CREATE POLICY "Authenticated users can upload news images" ON storage.objects
    FOR INSERT TO authenticated WITH CHECK (bucket_id = 'news-images');

-- UPDATE: Authenticated kullanıcılar güncelleyebilsin
DROP POLICY IF EXISTS "News authors can update images" ON storage.objects;
CREATE POLICY "News authors can update images" ON storage.objects
    FOR UPDATE TO authenticated USING (bucket_id = 'news-images')
    WITH CHECK (bucket_id = 'news-images');

-- DELETE: Sadece adminler silebilsin
DROP POLICY IF EXISTS "Only admins can delete images" ON storage.objects;
CREATE POLICY "Only admins can delete images" ON storage.objects
    FOR DELETE TO authenticated USING (
        bucket_id = 'news-images' AND
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
              AND profiles.role = 'admin'
        )
    );

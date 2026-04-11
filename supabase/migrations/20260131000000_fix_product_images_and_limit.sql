-- Çoklu ürün görseli desteği için ek alan
ALTER TABLE products
ADD COLUMN IF NOT EXISTS additional_images JSONB DEFAULT '[]'::jsonb;

COMMENT ON COLUMN products.additional_images IS 'Ek ürün görselleri URL listesi: ["url1", "url2", ...]';

-- Story bucket RLS politikalarını düzelt
-- Mevcut politikaları temizle
DROP POLICY IF EXISTS "Story bucket upload policy" ON storage.objects;
DROP POLICY IF EXISTS "Story bucket public read policy" ON storage.objects;
DROP POLICY IF EXISTS "Story bucket delete policy" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload stories" ON storage.objects;
DROP POLICY IF EXISTS "Users can view stories" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own stories" ON storage.objects;
DROP POLICY IF EXISTS "stories_upload_policy" ON storage.objects;
DROP POLICY IF EXISTS "stories_select_policy" ON storage.objects;
DROP POLICY IF EXISTS "stories_delete_policy" ON storage.objects;

-- Story bucket için yeni politikalar
CREATE POLICY "stories_upload_new"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'stories');

CREATE POLICY "stories_select_new"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'stories');

CREATE POLICY "stories_update_new"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'stories');

CREATE POLICY "stories_delete_new"
ON storage.objects
FOR DELETE
TO authenticated
USING (bucket_id = 'stories');

-- Stories bucket'ın var olduğundan emin ol
INSERT INTO storage.buckets (id, name, public)
VALUES ('stories', 'stories', true)
ON CONFLICT (id) DO UPDATE SET public = true;

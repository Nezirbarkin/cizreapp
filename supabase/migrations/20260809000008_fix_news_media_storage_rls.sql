-- Haber medya yüklemelerinde 403 üreten Storage RLS politikalarını düzeltir.
-- Nesneler `{auth.uid()}/...` altında tutulur; haberci yalnızca kendi klasörünü,
-- admin ise bütün haber medyalarını yönetebilir.

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'news-images',
  'news-images',
  true,
  104857600,
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4',
    'video/quicktime',
    'video/webm'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Public can access news images by name" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload news images" ON storage.objects;
DROP POLICY IF EXISTS "News authors can update images" ON storage.objects;
DROP POLICY IF EXISTS "Only admins can delete images" ON storage.objects;
DROP POLICY IF EXISTS "News media public read" ON storage.objects;
DROP POLICY IF EXISTS "News media owner insert" ON storage.objects;
DROP POLICY IF EXISTS "News media owner update" ON storage.objects;
DROP POLICY IF EXISTS "News media owner delete" ON storage.objects;

CREATE POLICY "News media public read"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'news-images');

CREATE POLICY "News media owner insert"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'news-images'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.role IN ('admin', 'news')
  )
);

CREATE POLICY "News media owner update"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'news-images'
  AND (
    (storage.foldername(name))[1] = (SELECT auth.uid())::text
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'admin'
    )
  )
)
WITH CHECK (
  bucket_id = 'news-images'
  AND (
    (storage.foldername(name))[1] = (SELECT auth.uid())::text
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'admin'
    )
  )
);

CREATE POLICY "News media owner delete"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'news-images'
  AND (
    (storage.foldername(name))[1] = (SELECT auth.uid())::text
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'admin'
    )
  )
);


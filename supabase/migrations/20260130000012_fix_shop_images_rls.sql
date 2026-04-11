-- shop-images bucket için RLS policy düzeltmesi
-- Önce mevcut policy'leri temizle
DROP POLICY IF EXISTS "Authenticated users can upload shop images" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own shop images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own shop images" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view shop images" ON storage.objects;

-- INSERT policy - Kullanıcılar kendi klasörüne yükleyebilir (userId/... formatı)
CREATE POLICY "Authenticated can upload shop images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'shop-images' AND
  (auth.uid())::text = (split_part(name, '/', 1))
);

-- SELECT policy - Herkes görebilir
CREATE POLICY "Public can view shop images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'shop-images');

-- UPDATE policy - Kullanıcı kendi dosyalarını güncelleyebilir
CREATE POLICY "Users can update own shop images"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'shop-images' AND
  (auth.uid())::text = (split_part(name, '/', 1))
)
WITH CHECK (
  bucket_id = 'shop-images' AND
  (auth.uid())::text = (split_part(name, '/', 1))
);

-- DELETE policy - Kullanıcı kendi dosyalarını silebilir
CREATE POLICY "Users can delete own shop images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'shop-images' AND
  (auth.uid())::text = (split_part(name, '/', 1))
);

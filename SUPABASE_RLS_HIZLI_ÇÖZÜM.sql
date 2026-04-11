-- Supabase SQL Editor'de çalıştırın!
-- Hızlı RLS politikası düzeltmesi

-- Tüm eski policies'i sil
DROP POLICY IF EXISTS "Authenticated can upload shop images" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Public view shop images" ON storage.objects;
DROP POLICY IF EXISTS "Users update own shop images" ON storage.objects;
DROP POLICY IF EXISTS "Users delete own shop images" ON storage.objects;
DROP POLICY IF EXISTS "Public can view shop images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated can upload shop images" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own shop images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own shop images" ON storage.objects;

-- Yeni doğru policies (shops/{shop_id}/filename formatı için)

-- INSERT: Sadece mağaza sahibi yükleyebilir
CREATE POLICY "Shop owners can upload images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'shop-images' AND 
  name LIKE 'shops/%' AND
  EXISTS (
    SELECT 1 FROM shops 
    WHERE id::text = split_part(name, '/', 2) 
    AND owner_id = auth.uid()
  )
);

-- SELECT: Herkes görebilir
CREATE POLICY "Public can view shop images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'shop-images');

-- UPDATE: Sadece mağaza sahibi güncelleyebilir
CREATE POLICY "Shop owners can update images"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'shop-images' AND 
  name LIKE 'shops/%' AND
  EXISTS (
    SELECT 1 FROM shops 
    WHERE id::text = split_part(name, '/', 2) 
    AND owner_id = auth.uid()
  )
)
WITH CHECK (
  bucket_id = 'shop-images' AND 
  name LIKE 'shops/%' AND
  EXISTS (
    SELECT 1 FROM shops 
    WHERE id::text = split_part(name, '/', 2) 
    AND owner_id = auth.uid()
  )
);

-- DELETE: Sadece mağaza sahibi silebilir
CREATE POLICY "Shop owners can delete images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'shop-images' AND 
  name LIKE 'shops/%' AND
  EXISTS (
    SELECT 1 FROM shops 
    WHERE id::text = split_part(name, '/', 2) 
    AND owner_id = auth.uid()
  )
);

-- Bilgi
SELECT 'RLS Policies updated successfully!' as status;

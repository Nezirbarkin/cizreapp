-- Supabase SQL Editor'de çalıştırın!
-- Tüm storage.objects policies'i silip yeniden oluştur

-- Tüm policies'i sil (IF EXISTS kullan)
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'storage' 
        AND tablename = 'objects'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', policy_record.policyname);
    END LOOP;
END $$;

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

SELECT 'RLS Policies updated successfully!' as status;

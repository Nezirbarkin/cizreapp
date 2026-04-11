-- Supabase SQL Editor'de çalıştırın!
-- RLS Policies - DOĞRU VERSIYON

-- Tüm policies'i sil
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

-- INSERT: Sadece mağaza sahibi yükleyebilir
CREATE POLICY "Shop owners can upload images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'shop-images' AND 
  name LIKE 'shops/%' AND
  EXISTS (
    SELECT 1 FROM shops 
    WHERE id::text = split_part(storage.objects.name, '/', 2) 
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
  storage.objects.name LIKE 'shops/%' AND
  EXISTS (
    SELECT 1 FROM shops 
    WHERE id::text = split_part(storage.objects.name, '/', 2) 
    AND owner_id = auth.uid()
  )
)
WITH CHECK (
  bucket_id = 'shop-images' AND 
  storage.objects.name LIKE 'shops/%' AND
  EXISTS (
    SELECT 1 FROM shops 
    WHERE id::text = split_part(storage.objects.name, '/', 2) 
    AND owner_id = auth.uid()
  )
);

-- DELETE: Sadece mağaza sahibi silebilir
CREATE POLICY "Shop owners can delete images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'shop-images' AND 
  storage.objects.name LIKE 'shops/%' AND
  EXISTS (
    SELECT 1 FROM shops 
    WHERE id::text = split_part(storage.objects.name, '/', 2) 
    AND owner_id = auth.uid()
  )
);

SELECT 'RLS Policies corrected successfully!' as status;

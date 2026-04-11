-- Fix shop-images bucket RLS policies to match actual upload path format
-- Path format: shops/{shop_id}/{filename}

-- Drop existing policies
DROP POLICY IF EXISTS "Users can upload to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Users can view own uploads" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own uploads" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own uploads" ON storage.objects;

-- Allow shop owners to insert images
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

-- Allow shop owners to view their images
CREATE POLICY "Shop owners can view images"
ON storage.objects FOR SELECT
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

-- Allow shop owners to update their images
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
);

-- Allow shop owners to delete their images
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

-- Allow public read access to shop images
CREATE POLICY "Public can view shop images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'shop-images');

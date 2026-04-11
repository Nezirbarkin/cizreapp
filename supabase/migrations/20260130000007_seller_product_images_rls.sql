-- Satıcıların ürün resimlerini yükleyebilmesi için Storage RLS Policy
-- Bu migration, satıcıların kendi mağaza klasörlerine resim yükleyebilmesini sağlar

-- Önce bucket'in var olduğunu kontrol et ve yoksa oluştur
INSERT INTO storage.buckets (id, name, public)
VALUES ('shop-images', 'shop-images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Mevcut policy'leri temizle (varsa)
DROP POLICY IF EXISTS "Sellers can upload product images" ON storage.objects;
DROP POLICY IF EXISTS "Sellers can view shop images" ON storage.objects;
DROP POLICY IF EXISTS "Public can view shop images" ON storage.objects;

-- Satıcıların kendi klasörlerine resim yükleyebilmesi
CREATE POLICY "Sellers can upload product images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'shop-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Satıcıların kendi klasöründeki resimleri görebilmesi
CREATE POLICY "Sellers can view shop images"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'shop-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Herkesin resimleri görebilmesi (public access)
CREATE POLICY "Public can view shop images"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'shop-images');

-- Satıcıların kendi resimlerini güncelleyebilmesi (replace)
CREATE POLICY "Sellers can replace product images"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'shop-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'shop-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Satıcıların kendi resimlerini silebilmesi
CREATE POLICY "Sellers can delete product images"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'shop-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

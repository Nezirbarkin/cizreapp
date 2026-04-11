-- Mağaza resimleri için Storage Bucket oluştur
-- shop-images bucket'ını oluştur

-- 1. Bucket'ı oluştur (eğer yoksa)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'shop-images',
  'shop-images',
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO NOTHING;

-- 2. Mevcut policy'leri temizle (hata önleme)
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Sellers can upload to their shop" ON storage.objects;
DROP POLICY IF EXISTS "Sellers can update their shop images" ON storage.objects;
DROP POLICY IF EXISTS "Sellers can delete their shop images" ON storage.objects;
DROP POLICY IF EXISTS "Admins can manage all shop images" ON storage.objects;
DROP POLICY IF EXISTS "shop_images_public_access" ON storage.objects;
DROP POLICY IF EXISTS "shop_images_seller_insert" ON storage.objects;
DROP POLICY IF EXISTS "shop_images_seller_update" ON storage.objects;
DROP POLICY IF EXISTS "shop_images_seller_delete" ON storage.objects;
DROP POLICY IF EXISTS "shop_images_admin_all" ON storage.objects;

-- 3. Public erişim için policy (herkes okuyabilir)
CREATE POLICY "shop_images_public_access"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'shop-images');

-- 4. Satıcılar kendi mağazalarına resim yükleyebilir
CREATE POLICY "shop_images_seller_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'shop-images' 
  AND (storage.foldername(name))[1] IN (
    SELECT id::text FROM public.shops WHERE owner_id = auth.uid()
  )
);

-- 5. Satıcılar kendi mağazalarının resimlerini güncelleyebilir
CREATE POLICY "shop_images_seller_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'shop-images'
  AND (storage.foldername(name))[1] IN (
    SELECT id::text FROM public.shops WHERE owner_id = auth.uid()
  )
);

-- 6. Satıcılar kendi mağazalarının resimlerini silebilir
CREATE POLICY "shop_images_seller_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'shop-images'
  AND (storage.foldername(name))[1] IN (
    SELECT id::text FROM public.shops WHERE owner_id = auth.uid()
  )
);

-- 7. Adminler tüm resimleri yönetebilir
CREATE POLICY "shop_images_admin_all"
ON storage.objects FOR ALL
TO authenticated
USING (
  bucket_id = 'shop-images'
  AND EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true
  )
);

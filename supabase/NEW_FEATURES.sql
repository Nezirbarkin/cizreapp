-- ============================================
-- KURYE SİSTEMİ VE STORAGE RLS - YENİ ÖZELLİKLER
-- ============================================
-- Bu SQL'i Supabase Dashboard > SQL Editor'da çalıştırın

-- 1. STORAGE RLS POLICY (Ürün resimleri için)
-- ============================================

-- Bucket'i oluştur (yoksa)
INSERT INTO storage.buckets (id, name, public)
VALUES ('shop-images', 'shop-images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Mevcut policy'leri temizle
DROP POLICY IF EXISTS "Sellers can upload product images" ON storage.objects;
DROP POLICY IF EXISTS "Sellers can view shop images" ON storage.objects;
DROP POLICY IF EXISTS "Public can view shop images" ON storage.objects;
DROP POLICY IF EXISTS "Sellers can replace product images" ON storage.objects;
DROP POLICY IF EXISTS "Sellers can delete product images" ON storage.objects;

-- Satıcıların kendi klasörüne resim yükleyebilmesi
CREATE POLICY "Sellers can upload product images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'shop-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Sat��cıların kendi klasöründeki resimleri görebilmesi
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

-- 2. KURYE SİSTEMİ (has_own_courier alanı)
-- ============================================

-- has_own_courier alanını ekle (zaten varsa hata vermez)
ALTER TABLE shops 
DROP COLUMN IF EXISTS has_own_courier;

ALTER TABLE shops 
ADD COLUMN has_own_courier BOOLEAN DEFAULT false;

-- Mevcut satıcılar için delivery_fee varsa has_own_courier'i true yap
UPDATE shops 
SET has_own_courier = true 
WHERE delivery_fee IS NOT NULL AND delivery_fee > 0;

-- Yorum ekle
COMMENT ON COLUMN shops.has_own_courier IS 'Satıcının kendi kuryesi var mı? True ise kendi teslimat ücretini belirler, false ise admin belirler';
COMMENT ON COLUMN shops.delivery_fee IS 'Satıcının kendi belirlediği teslimat ücreti (sadece has_own_courier=true ise kullanılır)';

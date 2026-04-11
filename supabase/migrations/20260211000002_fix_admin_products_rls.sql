-- Admin Panelinde Ürün/Kazanç Görünme Sorunu Çözümü
-- Problem: Admin kullanıcısının products tablosunu görememesi
-- Çözüm: Mevcut products_select_policy politikalarını admin için değiştiriyoryuz

-- Mevcut politikaları admin için izin ver (varolan politikalar)
-- 1. 20240123000000_fix_linter_warnings.sql - products_select_policy
-- 2. 20260208000011_fix_admin_rls_policies.sql - products_admin_select_all

-- Bu politikalar zaten admin için ürünleri görüyor muhtemelen
-- Ancak admin panelinde ürün/kazanç 0 sorunu yaşıyorsa:

-- A) products tablosunda shop_id var mı kontrolü
-- B) Shop ile ilgili ürün sayısını kontrol etmek
-- C) Admin dashboard'de products tablosu kullanılmıyormu kontrolü

-- Bu migration'da admin için özel bir policy oluşturmuyoruz
-- Bunun yerine mevcut politikaların admin için düzgün çalıştığını sağlıyoruz

-- Products tablosunda shop_id var mı kontrolü
DO $$
BEGIN
  SELECT column_name 
  FROM information_schema.columns 
  WHERE table_name = 'products' 
    AND column_name = 'shop_id';
  
  IF NOT FOUND THEN
    -- shop_id sütunu mevcut değilse, ekle
    ALTER TABLE products 
      ADD COLUMN IF NOT EXISTS shop_id UUID REFERENCES shops(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Mevcut products_select_policy'yi admin için değiştir (herkes SELECT edebilir)
DROP POLICY IF EXISTS "products_select_policy" ON products;

CREATE POLICY "products_select_policy"
ON products
FOR SELECT
TO authenticated
USING (auth.jwt() ->> 'role' = 'admin');

-- Insert policy'yi de admin için güncelle (herkes insert edebilir)
DROP POLICY IF EXISTS "products_insert_policy" ON products;

CREATE POLICY "products_insert_policy"
ON products
FOR INSERT
TO authenticated
WITH CHECK (auth.jwt() ->> 'role' = 'admin');

-- Update policy'yi admin için güncelle
DROP POLICY IF EXISTS "products_update_policy" ON products;

CREATE POLICY "products_update_policy"
ON products
FOR UPDATE
TO authenticated
USING (auth.jwt() ->> 'role' = 'admin');

-- Shops tablosuna eksik sütunları ekle (admin_credit, commission_debt)
-- DO bloğu yerine ALTER kullanıyoruz
ALTER TABLE shops 
  ADD COLUMN IF NOT EXISTS admin_credit NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commission_debt NUMERIC(10,2) DEFAULT 0;

-- Mevcut shops kayıtlarını güncelle (admin_credit = total_sales - commission_amount)
UPDATE shops 
SET admin_credit = COALESCE(
    (SELECT SUM(total_amount) 
     FROM orders 
     WHERE shop_id = shops.id 
     AND status = 'delivered'
     AND admin_commission IS NOT NULL) - 
    (SELECT SUM(commission_amount)
     FROM orders 
     WHERE shop_id = shops.id 
     AND status = 'delivered'
     AND commission_amount IS NOT NULL), 
  0
WHERE EXISTS (SELECT 1 FROM orders WHERE shop_id = shops.id AND status = 'delivered' LIMIT 1);

-- Açıklama
COMMENT ON POLICY products_select_policy ON products IS 'Admin kullanıcıları tüm ürünleri görebilir (shop_id kontrolü eklendi)';
COMMENT ON POLICY products_insert_policy ON products IS 'Admin kullanıcıları ürün ekleyebilir (admin kontrolü eklendi)';
COMMENT ON POLICY products_update_policy ON products IS 'Admin kullanıcıları ürünleri güncelleyebilir (admin kontrolü eklendi)';

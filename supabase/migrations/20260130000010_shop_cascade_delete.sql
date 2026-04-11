-- Satıcının dükkanını silme yetkisi + CASCADE delete
-- Satıcı silindiğinde tüm ilişkili veriler (ürünler, siparişler, yorumlar) de silinsin

-- 1. Önce mevcut foreign key constraint'leri kaldır ve CASCADE ile yeniden ekle

-- products.shop_id -> shops.id (CASCADE)
ALTER TABLE products 
DROP CONSTRAINT IF EXISTS products_shop_id_fkey,
ADD CONSTRAINT products_shop_id_fkey 
  FOREIGN KEY (shop_id) 
  REFERENCES shops(id) 
  ON DELETE CASCADE;

-- order_items.shop_id -> shops.id (CASCADE)
ALTER TABLE order_items 
DROP CONSTRAINT IF EXISTS order_items_shop_id_fkey,
ADD CONSTRAINT order_items_shop_id_fkey 
  FOREIGN KEY (shop_id) 
  REFERENCES shops(id) 
  ON DELETE CASCADE;

-- shop_reviews.shop_id -> shops.id (CASCADE)
ALTER TABLE shop_reviews 
DROP CONSTRAINT IF EXISTS shop_reviews_shop_id_fkey,
ADD CONSTRAINT shop_reviews_shop_id_fkey 
  FOREIGN KEY (shop_id) 
  REFERENCES shops(id) 
  ON DELETE CASCADE;

-- payout_requests.shop_id -> shops.id (CASCADE) (eğer varsa)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'payout_requests_shop_id_fkey'
    ) THEN
        ALTER TABLE payout_requests 
        DROP CONSTRAINT IF EXISTS payout_requests_shop_id_fkey,
        ADD CONSTRAINT payout_requests_shop_id_fkey 
          FOREIGN KEY (shop_id) 
          REFERENCES shops(id) 
          ON DELETE CASCADE;
    END IF;
END $$;

-- 2. Satıcının kendi dükkanını silme yetkisi için RLS policy
CREATE POLICY "Satıcılar kendi dükkanlarını silebilir"
ON shops
FOR DELETE
TO authenticated
USING (
  auth.uid() = owner_id
);

-- 3. Bilgi mesajı
COMMENT ON POLICY "Satıcılar kendi dükkanlarını silebilir" ON shops IS 
'Satıcı dükkanını sildiğinde tüm ürünler, siparişler ve yorumlar da CASCADE ile silinir';

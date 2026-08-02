-- =====================================================
-- DOSYA: supabase/migrations/20260728000003_market_fixes.sql
-- AMAÇ: Cart unique constraint + product search index + sales_count
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. Cart tablosuna unique constraint ekle (aynı ürün + aynı varyanttan 1 satır)
-- Önce duplicate'leri temizle
DELETE FROM cart a USING cart b
WHERE a.id < b.id
  AND a.user_id = b.user_id
  AND a.product_id = b.product_id
  AND COALESCE(a.variant_data::text, '') = COALESCE(b.variant_data::text, '');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'cart_user_product_variant_unique'
  ) THEN
    ALTER TABLE cart ADD CONSTRAINT cart_user_product_variant_unique
      UNIQUE (user_id, product_id, variant_data);
  END IF;
END $$;

-- 2. Product search için GIN index (full-text search)
CREATE INDEX IF NOT EXISTS idx_products_name_search
  ON products USING gin (to_tsvector('simple', name));
CREATE INDEX IF NOT EXISTS idx_products_desc_search
  ON products USING gin (to_tsvector('simple', description));

-- 3. Composite index - mağaza + kategori + fiyat filtreleri
CREATE INDEX IF NOT EXISTS idx_products_shop_available_created
  ON products (shop_id, is_available, created_at DESC)
  WHERE is_available = TRUE;

CREATE INDEX IF NOT EXISTS idx_products_category_price
  ON products (category, price)
  WHERE is_available = TRUE;

-- 4. products tablosuna sales_count kolonu (popularity için)
ALTER TABLE products ADD COLUMN IF NOT EXISTS sales_count INTEGER DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_products_sales_count
  ON products (sales_count DESC) WHERE is_available = TRUE;

-- 5. Sipariş tamamlandığında sales_count artıran trigger
CREATE OR REPLACE FUNCTION increase_product_sales_count()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
    UPDATE products p
    SET sales_count = p.sales_count + oi.quantity
    FROM order_items oi
    WHERE oi.order_id = NEW.id
      AND oi.product_id = p.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_increase_sales_count ON orders;
CREATE TRIGGER trg_increase_sales_count
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION increase_product_sales_count();

-- 6. Shop delivery info toplu getirme (N+1 çözümü)
CREATE OR REPLACE FUNCTION get_shops_delivery_info(p_shop_ids UUID[])
RETURNS TABLE (
  shop_id UUID,
  delivery_fee NUMERIC,
  free_delivery_min_amount NUMERIC,
  name TEXT
)
LANGUAGE sql
STABLE
AS $$
  SELECT id, delivery_fee, free_delivery_min_amount, name
  FROM shops
  WHERE id = ANY(p_shop_ids);
$$;

REVOKE ALL ON FUNCTION get_shops_delivery_info(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_shops_delivery_info(UUID[]) TO authenticated;

-- 7. RLS - products public selectable
DROP POLICY IF EXISTS "Anyone can view available products" ON products;
CREATE POLICY "Anyone can view available products" ON products
  FOR SELECT TO anon, authenticated
  USING (is_available = TRUE);

-- 8. Cart RLS kontrolü
DROP POLICY IF EXISTS "Users manage own cart" ON cart;
CREATE POLICY "Users manage own cart" ON cart
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 9. Test query
-- SELECT * FROM get_shops_delivery_info(ARRAY[]::UUID[]);

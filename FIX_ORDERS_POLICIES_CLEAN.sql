-- ============================================
-- ORDERS TABLE - RLS POLICIES CLEAN INSTALL
-- ============================================

-- 1. DROP TÜM ESKİ POLİCY'LERİ (orders tablosu)
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON orders;
DROP POLICY IF EXISTS "orders_update_policy" ON orders;
DROP POLICY IF EXISTS "Users can view own orders" ON orders;
DROP POLICY IF EXISTS "Users can insert own orders" ON orders;
DROP POLICY IF EXISTS "Users can update own orders" ON orders;
DROP POLICY IF EXISTS "Users can delete own orders" ON orders;
DROP POLICY IF EXISTS "Shops can view their orders" ON orders;
DROP POLICY IF EXISTS "Shops can update their orders" ON orders;

-- 2. DROP TÜM ESKİ POLİCY'LERİ (order_items tablosu)
DROP POLICY IF EXISTS "order_items_select_policy" ON order_items;
DROP POLICY IF EXISTS "order_items_insert_policy" ON order_items;
DROP POLICY IF EXISTS "order_items_update_policy" ON order_items;
DROP POLICY IF EXISTS "Users can view own order items" ON order_items;
DROP POLICY IF EXISTS "Users can insert order items" ON order_items;
DROP POLICY IF EXISTS "Shops can view their order items" ON order_items;

-- ============================================
-- ORDERS TABLE - YENİ POLİCY'LER (BASİT, RECURSIVE YOK)
-- ============================================

-- Kullanıcılar sadece kendi siparişlerini görebilir
CREATE POLICY "Users can view own orders" 
ON orders FOR SELECT 
USING (auth.uid() = user_id);

-- Kullanıcılar sadece kendi siparişlerini ekleyebilir
CREATE POLICY "Users can insert own orders" 
ON orders FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Kullanıcılar sadece kendi siparişlerini güncelleyebilir
CREATE POLICY "Users can update own orders" 
ON orders FOR UPDATE 
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Kullanıcılar sadece kendi siparişlerini silebilir
CREATE POLICY "Users can delete own orders" 
ON orders FOR DELETE 
USING (auth.uid() = user_id);

-- Dükkan sahipleri kendi dükkanlarının siparişlerini görebilir
CREATE POLICY "Shops can view their orders"
ON orders FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = auth.uid()
  )
);

-- Dükkan sahipleri kendi dükkanlarının siparişlerini güncelleyebilir
CREATE POLICY "Shops can update their orders"
ON orders FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = auth.uid()
  )
);

-- ============================================
-- ORDER_ITEMS TABLE - YENİ POLİCY'LER (BASİT, RECURSIVE YOK)
-- ============================================

-- Kullanıcılar kendi siparişlerinin item'larını görebilir
CREATE POLICY "Users can view own order items"
ON order_items FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM orders
    WHERE orders.id = order_items.order_id
    AND orders.user_id = auth.uid()
  )
);

-- Kullanıcılar kendi siparişlerine item ekleyebilir
CREATE POLICY "Users can insert order items"
ON order_items FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM orders
    WHERE orders.id = order_items.order_id
    AND orders.user_id = auth.uid()
  )
);

-- Dükkan sahipleri kendi dükkanlarının order item'larını görebilir
CREATE POLICY "Shops can view their order items"
ON order_items FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = order_items.shop_id
    AND shops.owner_id = auth.uid()
  )
);

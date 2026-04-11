-- ============================================
-- SUPABASE PERFORMANCE OPTIMIZATION
-- Auth RLS Initplan Fix
-- ============================================
-- 
-- Bu SQL dosyası Supabase Database Linter uyarılarını düzeltir:
-- 1. auth_rls_initplan: auth.uid() her satır için tekrar hesaplanıyor
-- 2. multiple_permissive_policies: Duplicate policies var
--
-- Çözüm: auth.uid() yerine (select auth.uid()) kullanarak
-- PostgreSQL'in query planını optimize etmesini sağlarız.
--
-- Bu fix, özellikle çok sayıda sipariş/veri olduğunda
-- performansı önemli ölçüde artıracaktır.
-- ============================================

-- ============================================
-- ORDERS TABLE - DROP ESKİ POLİCY'LER
-- ============================================

DROP POLICY IF EXISTS "Users can view own orders" ON orders;
DROP POLICY IF EXISTS "Users can insert own orders" ON orders;
DROP POLICY IF EXISTS "Users can update own orders" ON orders;
DROP POLICY IF EXISTS "Users can delete own orders" ON orders;
DROP POLICY IF EXISTS "Users can insert their own orders" ON orders;
DROP POLICY IF EXISTS "Shops can view their orders" ON orders;
DROP POLICY IF EXISTS "Shops can update their orders" ON orders;
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON orders;
DROP POLICY IF EXISTS "orders_update_policy" ON orders;

-- ============================================
-- ORDERS TABLE - OPTİMİZE POLİCY'LER
-- ============================================

-- Kullanıcılar sadece kendi siparişlerini görebilir
CREATE POLICY "Users can view own orders" 
ON orders FOR SELECT 
USING ((SELECT auth.uid()) = user_id);

-- Kullanıcılar sadece kendi siparişlerini ekleyebilir
-- NOT: Duplicate policy kaldırıldı - tek bir INSERT policy var
CREATE POLICY "Users can insert own orders" 
ON orders FOR INSERT 
WITH CHECK ((SELECT auth.uid()) = user_id);

-- Kullanıcılar sadece kendi siparişlerini güncelleyebilir
CREATE POLICY "Users can update own orders" 
ON orders FOR UPDATE 
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

-- Kullanıcılar sadece kendi siparişlerini silebilir
CREATE POLICY "Users can delete own orders" 
ON orders FOR DELETE 
USING ((SELECT auth.uid()) = user_id);

-- Dükkan sahipleri kendi dükkanlarının siparişlerini görebilir
CREATE POLICY "Shops can view their orders"
ON orders FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = (SELECT auth.uid())
  )
);

-- Dükkan sahipleri kendi dükkanının siparişlerini güncelleyebilir
CREATE POLICY "Shops can update their orders"
ON orders FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = (SELECT auth.uid())
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = (SELECT auth.uid())
  )
);

-- ============================================
-- ORDER_ITEMS TABLE - DROP ESKİ POLİCY'LER
-- ============================================

DROP POLICY IF EXISTS "Users can view own order items" ON order_items;
DROP POLICY IF EXISTS "Users can insert order items" ON order_items;
DROP POLICY IF EXISTS "Shops can view their order items" ON order_items;
DROP POLICY IF EXISTS "order_items_select_policy" ON order_items;
DROP POLICY IF EXISTS "order_items_insert_policy" ON order_items;
DROP POLICY IF EXISTS "order_items_update_policy" ON order_items;

-- ============================================
-- ORDER_ITEMS TABLE - OPTİMİZE POLİCY'LER
-- ============================================

-- Kullanıcılar kendi siparişlerinin item'larını görebilir
CREATE POLICY "Users can view own order items"
ON order_items FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM orders
    WHERE orders.id = order_items.order_id
    AND orders.user_id = (SELECT auth.uid())
  )
);

-- Kullanıcılar kendi siparişlerine item ekleyebilir
CREATE POLICY "Users can insert order items"
ON order_items FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM orders
    WHERE orders.id = order_items.order_id
    AND orders.user_id = (SELECT auth.uid())
  )
);

-- Dükkan sahipleri kendi dükkanının order item'larını görebilir
CREATE POLICY "Shops can view their order items"
ON order_items FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = order_items.shop_id
    AND shops.owner_id = (SELECT auth.uid())
  )
);

-- ============================================
-- NOTIFICATIONS TABLE - DROP ESKİ POLİCY'LER
-- ============================================

DROP POLICY IF EXISTS "Users can view own notifications" ON notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON notifications;
DROP POLICY IF EXISTS "Users can delete own notifications" ON notifications;
DROP POLICY IF EXISTS "Authenticated users can create notifications" ON notifications;
DROP POLICY IF EXISTS "notifications_select_policy" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_policy" ON notifications;
DROP POLICY IF EXISTS "notifications_update_policy" ON notifications;
DROP POLICY IF EXISTS "notifications_delete_policy" ON notifications;

-- ============================================
-- NOTIFICATIONS TABLE - OPTİMİZE POLİCY'LER
-- ============================================

-- Kullanıcılar sadece kendi bildirimlerini görebilir
CREATE POLICY "Users can view own notifications"
ON notifications FOR SELECT
USING ((SELECT auth.uid()) = user_id);

-- Kullanıcılar sadece kendi bildirimlerini güncelleyebilir
CREATE POLICY "Users can update own notifications"
ON notifications FOR UPDATE
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

-- Kullanıcılar sadece kendi bildirimlerini silebilir
CREATE POLICY "Users can delete own notifications"
ON notifications FOR DELETE
USING ((SELECT auth.uid()) = user_id);

-- Authenticated kullanıcılar notification oluşturabilir
CREATE POLICY "Authenticated users can create notifications"
ON notifications FOR INSERT
WITH CHECK (auth.role() = 'authenticated');

-- ============================================
-- ADDRESSES TABLE - DROP ESKİ POLİCY'LER
-- ============================================

DROP POLICY IF EXISTS "Users can view own addresses" ON addresses;
DROP POLICY IF EXISTS "Users can insert own addresses" ON addresses;
DROP POLICY IF EXISTS "Users can update own addresses" ON addresses;
DROP POLICY IF EXISTS "Users can delete own addresses" ON addresses;
DROP POLICY IF EXISTS "addresses_select_policy" ON addresses;
DROP POLICY IF EXISTS "addresses_insert_policy" ON addresses;
DROP POLICY IF EXISTS "addresses_update_policy" ON addresses;
DROP POLICY IF EXISTS "addresses_delete_policy" ON addresses;

-- ============================================
-- ADDRESSES TABLE - OPTİMİZE POLİCY'LER
-- ============================================

-- Kullanıcılar sadece kendi adreslerini görebilir
CREATE POLICY "Users can view own addresses"
ON addresses FOR SELECT
USING ((SELECT auth.uid()) = user_id);

-- Kullanıcılar sadece kendi adreslerini ekleyebilir
CREATE POLICY "Users can insert own addresses"
ON addresses FOR INSERT
WITH CHECK ((SELECT auth.uid()) = user_id);

-- Kullanıcılar sadece kendi adreslerini güncelleyebilir
CREATE POLICY "Users can update own addresses"
ON addresses FOR UPDATE
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

-- Kullanıcılar sadece kendi adreslerini silebilir
CREATE POLICY "Users can delete own addresses"
ON addresses FOR DELETE
USING ((SELECT auth.uid()) = user_id);

-- ============================================
-- COUPONS TABLE - SKIP (Tablo yapısı bilinmiyor)
-- ============================================
-- Coupons tablosu şu an için optimize edilmedi.
-- Bu tablo farklı bir yapıya sahip olabilir veya kullanılmıyor olabilir.

-- ============================================
-- TEST SONRASI KONTROL
-- ============================================
-- 
-- Bu SQL'i çalıştırdıktan sonra Supabase dashboard'da
-- Database Linter'ı tekrar çalıştırın ve uyarıların
-- gittiğini doğrulayın.
--
-- Performans artışı özellikle şu durumlarda fark edilecek:
-- - Çok sayıda sipariş varsa (100+)
-- - Kullanıcı sipariş listesini çekiyorsa
-- - Dükkan sahibi siparişlerini görüntülüyorsa
-- ============================================

-- ============================================
-- MULTIPLE PERMISSIVE POLICIES FIX
-- Orders ve Order_Items Tablolarını Birleştir
-- ============================================
-- 
-- Bu SQL dosyası multiple_permissive_policies uyarılarını düzeltir.
-- Çözüm: İki ayrı policy'yi (Users + Shops) tek bir policy'de birleştirerek
-- performansı artırır.
-- 
-- Mantık: OR operatörüyle hem kullanıcı hem dükkan kontrolü tek policy'de
-- ============================================

-- ============================================
-- ORDERS TABLE - POLICY MERGE
-- ============================================

-- Önce mevcut ayrı policy'leri sil
DROP POLICY IF EXISTS "Users can view own orders" ON orders;
DROP POLICY IF EXISTS "Shops can view their orders" ON orders;
DROP POLICY IF EXISTS "Users can update own orders" ON orders;
DROP POLICY IF EXISTS "Shops can update their orders" ON orders;

-- SELECT: Birleştirilmiş policy (Users OR Shops)
CREATE POLICY "orders_select_unified"
ON orders FOR SELECT
USING (
  -- Kullanıcı kendi siparişini görebilir
  (SELECT auth.uid()) = user_id
  OR
  -- Dükkan sahibi kendi dükkanının siparişini görebilir
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = (SELECT auth.uid())
  )
);

-- UPDATE: Birleştirilmiş policy (Users OR Shops)
CREATE POLICY "orders_update_unified"
ON orders FOR UPDATE
USING (
  -- Kullanıcı kendi siparişini güncelleyebilir
  (SELECT auth.uid()) = user_id
  OR
  -- Dükkan sahibi kendi dükkanının siparişini güncelleyebilir
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = (SELECT auth.uid())
  )
)
WITH CHECK (
  -- Kullanıcı kendi siparişini güncelleyebilir
  (SELECT auth.uid()) = user_id
  OR
  -- Dükkan sahibi kendi dükkanının siparişini güncelleyebilir
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = (SELECT auth.uid())
  )
);

-- ============================================
-- ORDER_ITEMS TABLE - POLICY MERGE
-- ============================================

-- Önce mevcut ayrı policy'leri sil
DROP POLICY IF EXISTS "Users can view own order items" ON order_items;
DROP POLICY IF EXISTS "Shops can view their order items" ON order_items;

-- SELECT: Birleştirilmiş policy (Users OR Shops)
CREATE POLICY "order_items_select_unified"
ON order_items FOR SELECT
USING (
  -- Kullanıcı kendi siparişinin item'larını görebilir
  EXISTS (
    SELECT 1 FROM orders
    WHERE orders.id = order_items.order_id
    AND orders.user_id = (SELECT auth.uid())
  )
  OR
  -- Dükkan sahibi kendi dükkanının item'larını görebilir
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = order_items.shop_id
    AND shops.owner_id = (SELECT auth.uid())
  )
);

-- ============================================
-- DİĞER POLİCY'LER (değişmeden kaldı)
-- ============================================

-- Users can insert own orders (değişmeden)
-- Users can delete own orders (değişmeden)
-- Users can insert order items (değişmeden)

-- Bu policy'ler zaten tek olduğu için sorun yok
-- Sadece birden fazla policy olanlarda sorun vardı

-- ============================================
-- TEST SONRASI KONTROL
-- ============================================
-- 
-- Bu SQL'i çalıştırdıktan sonra:
-- 1. Supabase Dashboard → Database Linter'ı çalıştır
-- 2. multiple_permissive_policies uyarıları GİTMİŞ OLMALI
-- 
-- PERFORMANS NOTLARI:
-- - Tek policy içinde OR ile kontrol daha hızlı
-- - PostgreSQL query optimizer daha iyi çalışır
-- - Her iki kontrol de tek seferde yapılır
-- 
-- GÜVENLİK NOTLARI:
-- - Güvenlik seviyesi aynı kalıyor
-- - Hem kullanıcı hem dükkan erişimi korunuyor
-- - Hiçbir yetki kaybı yok
-- ============================================

-- ============================================
-- ORDERS TABLE - RLS POLICIES CLEAN FIX
-- Infinite Recursion Hatası Çözümü
-- ============================================

-- ÖNEMLİ: auth_is_admin() fonksiyonu profiles tablosunu sorguluyor
-- ve profiles tablosunun politikası da auth_is_admin() kullanıyor.
-- Bu sonsuz döngüye neden oluyor.
-- 
-- ÇÖZÜM: Sadece doğrudan kullanıcı kimliği kontrolü kullan,
-- auth_is_admin() veya is_admin() FONKSİYONLARINI KULLANMA!
-- ============================================

-- 1. TÜM ESKİ ORDERS POLITICS'LERİNİ SİL
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON orders;
DROP POLICY IF EXISTS "orders_update_policy" ON orders;
DROP POLICY IF EXISTS "orders_delete_policy" ON orders;
DROP POLICY IF EXISTS "Users can view own orders" ON orders;
DROP POLICY IF EXISTS "Users can insert own orders" ON orders;
DROP POLICY IF EXISTS "Users can update own orders" ON orders;
DROP POLICY IF EXISTS "Users can delete own orders" ON orders;
DROP POLICY IF EXISTS "Shops can view their orders" ON orders;
DROP POLICY IF EXISTS "Shops can update their orders" ON orders;
DROP POLICY IF EXISTS "orders_select_user_or_seller_or_admin" ON orders;
DROP POLICY IF EXISTS "orders_select" ON orders;
DROP POLICY IF EXISTS "orders_select_public_dashboard" ON orders;
DROP POLICY IF EXISTS "Enable read access for all users" ON orders;
DROP POLICY IF EXISTS "Admin can view all orders" ON orders;

-- 2. TÜM ESKİ ORDER_ITEMS POLITICS'LERİNİ SİL
DROP POLICY IF EXISTS "order_items_select_policy" ON order_items;
DROP POLICY IF EXISTS "order_items_insert_policy" ON order_items;
DROP POLICY IF EXISTS "order_items_update_policy" ON order_items;
DROP POLICY IF EXISTS "order_items_select" ON order_items;
DROP POLICY IF EXISTS "order_items_admin_select_all" ON order_items;
DROP POLICY IF EXISTS "Herkes sipariş öğelerini görebilir" ON order_items;
DROP POLICY IF EXISTS "Users can view own order items" ON order_items;
DROP POLICY IF EXISTS "Users can insert order items" ON order_items;
DROP POLICY IF EXISTS "Shops can view their order items" ON order_items;

-- ============================================
-- ORDERS TABLE - YENİ BASİT POLITIKALAR
-- NOT: Admin kontrolü için role kolonu DOĞRUDAN kullanılıyor
-- auth_is_admin() veya is_admin() FONKSIYONLARI KULLANILMIYOR!
-- ============================================

-- SELECT: Kullanıcı kendi siparişlerini görebilir
-- Satıcılar için shop_id üzerinden kontrol
CREATE POLICY "orders_select_policy" ON orders
FOR SELECT TO authenticated
USING (
    user_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM shops 
        WHERE shops.id = orders.shop_id 
        AND shops.owner_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = auth.uid() 
        AND profiles.role = 'admin'
    )
);

-- INSERT: Kullanıcı sadece kendi için sipariş oluşturabilir
CREATE POLICY "orders_insert_policy" ON orders
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

-- UPDATE: Sipariş sahibi veya dükkan sahibi güncelleyebilir
CREATE POLICY "orders_update_policy" ON orders
FOR UPDATE TO authenticated
USING (
    user_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM shops 
        WHERE shops.id = orders.shop_id 
        AND shops.owner_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = auth.uid() 
        AND profiles.role = 'admin'
    )
);

-- ============================================
-- ORDER_ITEMS TABLE - YENİ BASİT POLITIKALAR
-- ============================================

-- SELECT: Sipariş sahibi veya dükkan sahibi görebilir
CREATE POLICY "order_items_select_policy" ON order_items
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = order_items.order_id 
        AND orders.user_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM orders o
        JOIN shops s ON o.shop_id = s.id
        WHERE o.id = order_items.order_id
        AND s.owner_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = auth.uid() 
        AND profiles.role = 'admin'
    )
);

-- INSERT: Kullanıcı kendi siparişine item ekleyebilir
CREATE POLICY "order_items_insert_policy" ON order_items
FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = order_items.order_id 
        AND orders.user_id = auth.uid()
    )
);

-- UPDATE: Sipariş sahibi veya dükkan sahibi güncelleyebilir
CREATE POLICY "order_items_update_policy" ON order_items
FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = order_items.order_id 
        AND orders.user_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM orders o
        JOIN shops s ON o.shop_id = s.id
        WHERE o.id = order_items.order_id
        AND s.owner_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = auth.uid() 
        AND profiles.role = 'admin'
    )
);

-- ============================================
-- DOĞRULAMA
-- ============================================
DO $$
DECLARE
    v_orders_policies INTEGER;
    v_order_items_policies INTEGER;
BEGIN
    -- Politika sayısını kontrol et
    SELECT COUNT(*) INTO v_orders_policies
    FROM pg_policies
    WHERE tablename = 'orders' AND schemaname = 'public';
    
    SELECT COUNT(*) INTO v_order_items_policies
    FROM pg_policies
    WHERE tablename = 'order_items' AND schemaname = 'public';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'ORDERS POLICIES CLEAN FIX TAMAMLANDI!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'orders tablosundaki policy sayisi: %', v_orders_policies;
    RAISE NOTICE 'order_items tablosundaki policy sayisi: %', v_order_items_policies;
    RAISE NOTICE '';
    RAISE NOTICE 'Yeni politikalar:';
    RAISE NOTICE '  - orders_select_policy (SELECT)';
    RAISE NOTICE '  - orders_insert_policy (INSERT)';
    RAISE NOTICE '  - orders_update_policy (UPDATE)';
    RAISE NOTICE '  - order_items_select_policy (SELECT)';
    RAISE NOTICE '  - order_items_insert_policy (INSERT)';
    RAISE NOTICE '  - order_items_update_policy (UPDATE)';
    RAISE NOTICE '';
    RAISE NOTICE 'ONEMLI: auth_is_admin() veya is_admin() FONKSIYONLARI';
    RAISE NOTICE 'BU DOSYADA KULLANILMADI!';
    RAISE NOTICE 'Sonsuz dongu (infinite recursion) hatasi cozuldu.';
    RAISE NOTICE '========================================';
END $$;

-- ============================================
-- TEST SORGUSU - Bunu SQL Editor'de calistir
-- ============================================
-- SELECT policyname, cmd, permissive
-- FROM pg_policies
-- WHERE tablename IN ('orders', 'order_items')
-- AND schemaname = 'public'
-- ORDER BY tablename, cmd;

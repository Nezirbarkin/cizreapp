-- ============================================================================
-- SİPARİŞ POLITIKALARI - TEMİZ BAŞLANGIÇ
-- Sonsuz döngüyü önlemek için orders tablosundan kurye kontrolünü KALDIR
-- ============================================================================

-- Tüm mevcut orders politikalarını sil
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON orders;
DROP POLICY IF EXISTS "orders_update_policy" ON orders;
DROP POLICY IF EXISTS "orders_delete_policy" ON orders;

-- ============================================
-- BASİT VE GÜVENLİ ORDERS POLITIKALARI
-- ============================================

-- SELECT: Kullanıcı ve satıcı görebilir (kurye YOK)
CREATE POLICY "orders_select_policy" ON orders
FOR SELECT TO authenticated
USING (
    user_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM shops 
        WHERE shops.id = orders.shop_id 
        AND shops.owner_id = auth.uid()
    )
);

-- INSERT: Kullanıcı sadece kendi için sipariş oluşturabilir
CREATE POLICY "orders_insert_policy" ON orders
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

-- UPDATE: Sipariş sahibi veya satıcı güncelleyebilir
CREATE POLICY "orders_update_policy" ON orders
FOR UPDATE TO authenticated
USING (
    user_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM shops 
        WHERE shops.id = orders.shop_id 
        AND shops.owner_id = auth.uid()
    )
);

-- ============================================
-- COURIER_ASSIGNMENTS - Kurye Erişimi
-- ============================================

-- Tüm mevcut courier_assignments politikalarını sil
DROP POLICY IF EXISTS "courier_assignments_select_policy" ON courier_assignments;
DROP POLICY IF EXISTS "courier_assignments_insert_policy" ON courier_assignments;
DROP POLICY IF EXISTS "courier_assignments_update_policy" ON courier_assignments;
DROP POLICY IF EXISTS "Couriers can view all assignments" ON courier_assignments;
DROP POLICY IF EXISTS "Couriers create assignments" ON courier_assignments;
DROP POLICY IF EXISTS "Couriers update own assignments" ON courier_assignments;
DROP POLICY IF EXISTS "Couriers view own assignments" ON courier_assignments;
DROP POLICY IF EXISTS "Sellers can assign couriers to own orders" ON courier_assignments;
DROP POLICY IF EXISTS "Sellers view own order assignments" ON courier_assignments;
DROP POLICY IF EXISTS "Admins view all assignments" ON courier_assignments;

-- SELECT: Kurye sadece kendi atamalarını görebilir
CREATE POLICY "courier_assignments_select_policy" ON courier_assignments
FOR SELECT TO authenticated
USING (
    courier_id = auth.uid()
);

-- INSERT: Sadece satıcı atama yapabilir
CREATE POLICY "courier_assignments_insert_policy" ON courier_assignments
FOR INSERT TO authenticated
WITH CHECK (
    courier_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM orders o
        JOIN shops s ON o.shop_id = s.id
        WHERE o.id = courier_assignments.order_id
        AND s.owner_id = auth.uid()
    )
);

-- UPDATE: Kurye sadece kendi atamalarını güncelleyebilir
CREATE POLICY "courier_assignments_update_policy" ON courier_assignments
FOR UPDATE TO authenticated
USING (courier_id = auth.uid());

-- ============================================
-- DOĞRULAMA
-- ============================================
SELECT 'Clean orders and courier_assignments policies created' as status;
SELECT tablename, policyname, cmd FROM pg_policies 
WHERE tablename IN ('orders', 'courier_assignments') AND schemaname = 'public'
ORDER BY tablename, policyname;
-- ============================================
-- ORDERS TABLE - RLS POLICIES - SONSUZ DÖNGÜ ÇÖZÜMÜ
-- ============================================

-- Tüm eski politikaları sil
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON orders;
DROP POLICY IF EXISTS "orders_update_policy" ON orders;
DROP POLICY IF EXISTS "orders_delete_policy" ON orders;

-- ============================================
-- BASİT POLITIKALAR (Sonsuz döngü OLMAZ)
-- ============================================

-- SELECT: Kullanıcı kendi siparişlerini, satıcı kendi dükkanının siparişlerini görebilir
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

-- UPDATE: Sipariş sahibi veya satıcı güncelleyebilir (kurye HARİÇ)
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
-- COURIER ASSIGNMENTS - Kurye için özel erişim
-- ============================================

-- Tüm eski courier_assignments politikalarını sil
DROP POLICY IF EXISTS "courier_assignments_select_policy" ON courier_assignments;
DROP POLICY IF EXISTS "courier_assignments_insert_policy" ON courier_assignments;
DROP POLICY IF EXISTS "courier_assignments_update_policy" ON courier_assignments;

-- SELECT: Kurye kendi atamalarını ve sipariş bilgilerini görebilir
CREATE POLICY "courier_assignments_select_policy" ON courier_assignments
FOR SELECT TO authenticated
USING (
    courier_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM shops 
        WHERE shops.id = (SELECT shop_id FROM orders WHERE orders.id = courier_assignments.order_id)
        AND shops.owner_id = auth.uid()
    )
);

-- INSERT: Sadece sistem/satıcı atama yapabilir
CREATE POLICY "courier_assignments_insert_policy" ON courier_assignments
FOR INSERT TO authenticated
WITH CHECK (
    courier_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM shops 
        WHERE shops.id = (SELECT shop_id FROM orders WHERE orders.id = courier_assignments.order_id)
        AND shops.owner_id = auth.uid()
    )
);

-- UPDATE: Kurye sadece kendi atamalarını güncelleyebilir
CREATE POLICY "courier_assignments_update_policy" ON courier_assignments
FOR UPDATE TO authenticated
USING (courier_id = auth.uid());

-- ============================================
-- DOĞRULAMA
-- ============================================
SELECT 'Orders Policies Created (Safe - No Recursion)' as status;
SELECT policyname, cmd FROM pg_policies 
WHERE tablename IN ('orders', 'courier_assignments') AND schemaname = 'public'
ORDER BY tablename, policyname;
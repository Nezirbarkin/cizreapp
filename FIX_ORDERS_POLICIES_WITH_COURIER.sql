-- ============================================
-- ORDERS TABLE - RLS POLICIES + COURIER ACCESS
-- ============================================

-- 1. TÜM ESKİ ORDERS POLICIES'LERİNİ SİL
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON orders;
DROP POLICY IF EXISTS "orders_update_policy" ON orders;
DROP POLICY IF EXISTS "orders_delete_policy" ON orders;

-- ============================================
-- ORDERS TABLE - YENİ POLITIKALAR (Kurye Dahil)
-- ============================================

-- SELECT: Kullanıcı, Satıcı, Admin ve Kurye görebilir
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
    OR EXISTS (
        SELECT 1 FROM courier_assignments 
        WHERE courier_assignments.order_id = orders.id 
        AND courier_assignments.courier_id = auth.uid()
    )
);

-- INSERT: Kullanıcı sadece kendi için sipariş oluşturabilir
CREATE POLICY "orders_insert_policy" ON orders
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

-- UPDATE: Sipariş sahibi, Satıcı, Admin ve Kurye güncelleyebilir
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
    OR EXISTS (
        SELECT 1 FROM courier_assignments 
        WHERE courier_assignments.order_id = orders.id 
        AND courier_assignments.courier_id = auth.uid()
    )
);

-- ============================================
-- DOĞRULAMA
-- ============================================
SELECT 'Orders Policies Created' as status;

-- Politikaları listele
SELECT policyname, cmd FROM pg_policies 
WHERE tablename = 'orders' AND schemaname = 'public'
ORDER BY policyname;
-- ============================================
-- ORDERS TABLE - RLS POLICIES - GERİ DÖNÜŞ
-- ============================================

-- Tüm eski politikaları sil
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON orders;
DROP POLICY IF EXISTS "orders_update_policy" ON orders;
DROP POLICY IF EXISTS "orders_delete_policy" ON orders;
DROP POLICY IF EXISTS "Couriers can view orders for delivery" ON orders;

-- ============================================
-- BASİT VE ÇALIŞAN POLITIKALAR
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

-- UPDATE: Sipariş sahibi, satıcı veya kurye güncelleyebilir
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
        SELECT 1 FROM courier_assignments 
        WHERE courier_assignments.order_id = orders.id 
        AND courier_assignments.courier_id = auth.uid()
    )
);

-- ============================================
-- DOĞRULAMA
-- ============================================
SELECT 'Orders Policies RESET Complete' as status;
SELECT policyname, cmd FROM pg_policies 
WHERE tablename = 'orders' AND schemaname = 'public'
ORDER BY policyname;
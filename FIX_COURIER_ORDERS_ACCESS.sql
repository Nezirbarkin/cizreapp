-- ============================================
-- COURIER_ASSIGNMENTS - Kurye Erişimi İçin RLS
-- ============================================

-- Mevcut courier_assignments politikalarını kontrol et
SELECT policyname, cmd FROM pg_policies 
WHERE tablename = 'courier_assignments' AND schemaname = 'public'
ORDER BY policyname;

-- ============================================
-- ÇÖZÜM: Kuryenin siparişleri görmesi için
-- orders tablosuna kurye SELECT izni ekle
-- ============================================

-- Mevcut orders_select_policy'yi güncelle
DROP POLICY IF EXISTS "orders_select_policy" ON orders;

CREATE POLICY "orders_select_policy" ON orders
FOR SELECT TO authenticated
USING (
    -- Kullanıcı kendi siparişlerini görebilir
    user_id = auth.uid()
    -- Satıcı kendi dükkanının siparişlerini görebilir
    OR EXISTS (
        SELECT 1 FROM shops 
        WHERE shops.id = orders.shop_id 
        AND shops.owner_id = auth.uid()
    )
    -- Kuryeler atanmış oldukları siparişleri görebilir
    OR EXISTS (
        SELECT 1 FROM courier_assignments 
        WHERE courier_assignments.order_id = orders.id 
        AND courier_assignments.courier_id = auth.uid()
    )
);

-- ============================================
-- DOĞRULAMA
-- ============================================
SELECT 'Orders SELECT policy updated - Courier access added' as status;
SELECT policyname, cmd FROM pg_policies 
WHERE tablename = 'orders' AND schemaname = 'public'
ORDER BY policyname;
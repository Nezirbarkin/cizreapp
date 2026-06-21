-- ============================================================================
-- EKLEME: Kuryelerin sipariş durumunu güncelleyebilmesi
-- ============================================================================
-- Sorun: Kurye teslim ettiğinde sipariş durumu güncellenemiyordu çünkü
-- RLS politikası kuryeye izin vermiyordu.
-- Çözüm: Kuryelerin kendilerine atanmış siparişleri güncelleyebilmesi
-- ============================================================================

-- Mevcut orders_update_policy'yi güncelle
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;

CREATE POLICY "orders_update_policy" ON public.orders
    FOR UPDATE TO authenticated
    USING (
        -- Sipariş sahibi güncelleyebilir
        user_id = (select auth.uid()) 
        -- Satıcı kendi dükkanına gelen siparişleri güncelleyebilir
        OR shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
        -- Admin her şeyi güncelleyebilir
        OR (select auth_is_admin()) = true
        -- Kurye kendisine atanmış siparişleri güncelleyebilir (status: on_the_way, delivered)
        OR EXISTS (
            SELECT 1 FROM public.courier_assignments 
            WHERE courier_assignments.order_id = orders.id 
            AND courier_assignments.courier_id = (select auth.uid())
        )
    )
    WITH CHECK (
        user_id = (select auth.uid()) 
        OR shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
        OR (select auth_is_admin()) = true
        OR EXISTS (
            SELECT 1 FROM public.courier_assignments 
            WHERE courier_assignments.order_id = orders.id 
            AND courier_assignments.courier_id = (select auth.uid())
        )
    );

-- SELECT policy'ye de kurye izni ekle (kendine atanan siparişleri görebilsin)
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;

CREATE POLICY "orders_select_policy" ON public.orders
    FOR SELECT TO authenticated
    USING (
        user_id = (select auth.uid()) 
        OR shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
        OR (select auth_is_admin()) = true
        OR EXISTS (
            SELECT 1 FROM public.courier_assignments 
            WHERE courier_assignments.order_id = orders.id 
            AND courier_assignments.courier_id = (select auth.uid())
        )
    );

-- Debug
RAISE NOTICE 'Courier orders update policy created successfully';

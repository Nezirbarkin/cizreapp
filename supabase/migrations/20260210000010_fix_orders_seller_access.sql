-- ============================================================================
-- FIX: Satıcıların sipariş erişim yetkisi
-- ============================================================================
-- SORUN: 20260210000004 migration'ında orders_select_policy satıcı kontrolü
-- (shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid())) çıkarılmış.
-- Bu nedenle satıcılar kendi dükkanlarına gelen siparişleri göremiyordu.
-- ============================================================================

-- SELECT Policy - Kullanıcı kendi siparişlerini, satıcı dükkan siparişlerini, admin tümünü görebilir
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
CREATE POLICY "orders_select_policy" ON public.orders
    FOR SELECT TO authenticated
    USING (
        user_id = (select auth.uid()) 
        OR shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
        OR (select auth_is_admin()) = true
    );

-- UPDATE Policy - Sipariş sahibi, satıcı ve admin güncelleyebilir
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;
CREATE POLICY "orders_update_policy" ON public.orders
    FOR UPDATE TO authenticated
    USING (
        user_id = (select auth.uid()) 
        OR shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
        OR (select auth_is_admin()) = true
    )
    WITH CHECK (
        user_id = (select auth.uid()) 
        OR shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
        OR (select auth_is_admin()) = true
    );

-- DELETE Policy - Sadece admin silebilir (değişiklik yok)
-- DROP POLICY IF EXISTS "orders_delete_policy" ON public.orders;
-- CREATE POLICY "orders_delete_policy" ON public.orders
--     FOR DELETE TO authenticated
--     USING ((select auth_is_admin()) = true);

-- ORDER_ITEMS da kontrol edelim
-- Satıcı order_items'ları da görebilmeli

-- order_items SELECT policy düzelt
DROP POLICY IF EXISTS "order_items_select_policy" ON public.order_items;
DROP POLICY IF EXISTS "order_items_select" ON public.order_items;
DROP POLICY IF EXISTS "Herkes sipariş öğelerini görebilir" ON public.order_items;
DROP POLICY IF EXISTS "order_items_select_optimized" ON public.order_items;

CREATE POLICY "order_items_select_policy" ON public.order_items
    FOR SELECT TO authenticated
    USING (
        -- Sipariş sahibi görebilir
        EXISTS (
            SELECT 1 FROM public.orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id = (select auth.uid())
        )
        -- Dükkan sahibi görebilir
        OR EXISTS (
            SELECT 1 FROM public.orders o
            JOIN public.shops s ON o.shop_id = s.id
            WHERE o.id = order_items.order_id
            AND s.owner_id = (select auth.uid())
        )
        -- Admin görebilir
        OR (select auth_is_admin()) = true
    );

-- order_items INSERT policy - Kullanıcı kendi siparişine item ekleyebilir
DROP POLICY IF EXISTS "order_items_insert_policy" ON public.order_items;
DROP POLICY IF EXISTS "order_items_insert" ON public.order_items;
DROP POLICY IF EXISTS "Kullanıcılar sipariş öğesi ekleyebilir" ON public.order_items;

CREATE POLICY "order_items_insert_policy" ON public.order_items
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id = (select auth.uid())
        )
    );

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Orders Seller Access Fix Applied!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Satıcılar artık kendi dükkan siparişlerini görebilir';
    RAISE NOTICE 'orders_select_policy: user + shop_owner + admin';
    RAISE NOTICE 'orders_update_policy: user + shop_owner + admin';
    RAISE NOTICE 'order_items_select_policy: order_user + shop_owner + admin';
    RAISE NOTICE '========================================';
END $$;

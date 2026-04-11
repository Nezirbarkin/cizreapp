-- =====================================================
-- FIX: Satıcıların Orders Tablosunu Update Etmesi
-- =====================================================
-- Satıcılar, kendi dükkanlarına gelen siparişlerin durumunu güncelleyebilmeli

-- Mevcut sellers_orders_update policy'sini sil (varsa)
DROP POLICY IF EXISTS sellers_orders_update ON public.orders;

-- Satıcıların kendi dükkanlarındaki siparişleri update etmesine izin veren policy
CREATE POLICY sellers_orders_update ON public.orders
    FOR UPDATE
    TO authenticated
    USING (
        -- Siparişin shop_id'si, satıcının dükkanı ile eşleşmeli
        EXISTS (
            SELECT 1 
            FROM public.shops 
            WHERE shops.id = orders.shop_id 
            AND shops.owner_id = (SELECT auth.uid())
        )
        -- Veya admin
        OR EXISTS (
            SELECT 1 
            FROM public.profiles 
            WHERE profiles.id = (SELECT auth.uid()) 
            AND profiles.role = 'admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 
            FROM public.shops 
            WHERE shops.id = orders.shop_id 
            AND shops.owner_id = (SELECT auth.uid())
        )
        OR EXISTS (
            SELECT 1 
            FROM public.profiles 
            WHERE profiles.id = (SELECT auth.uid()) 
            AND profiles.role = 'admin'
        )
    );

COMMENT ON POLICY sellers_orders_update ON public.orders IS 'Satıcılar kendi dükkanlarındaki siparişleri güncelleyebilir';

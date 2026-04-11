-- =====================================================
-- FIX: Satıcılar Sipariş Adreslerini Göremiyor
-- =====================================================
-- Satıcılar, kendi dükkanlarına gelen siparişlerdeki
-- müşteri adreslerini görebilmelidir.

-- Mevcut adreslere satıcı erişimi için policy ekle
CREATE POLICY sellers_view_order_addresses ON public.addresses
    FOR SELECT
    TO authenticated
    USING (
        -- Kendi adresleri
        user_id = (SELECT auth.uid())
        OR
        -- Veya bu adresin kullanıldığı bir sipariş, satıcının dükkanına aitse
        EXISTS (
            SELECT 1 
            FROM public.orders o
            INNER JOIN public.shops s ON s.id = o.shop_id
            WHERE o.address_id = addresses.id
            AND s.owner_id = (SELECT auth.uid())
        )
        OR
        -- Veya admin
        EXISTS (
            SELECT 1 
            FROM public.profiles 
            WHERE profiles.id = (SELECT auth.uid()) 
            AND profiles.role = 'admin'
        )
    );

COMMENT ON POLICY sellers_view_order_addresses ON public.addresses IS 
'Satıcılar kendi dükkanlarındaki siparişlerin adreslerini görebilir';

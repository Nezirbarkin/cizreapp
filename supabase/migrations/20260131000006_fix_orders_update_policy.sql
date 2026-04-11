-- Orders tablosu için UPDATE policy'leri birleştir
-- Mükerrer policy uyarısını düzeltmek için tek birleşik policy

-- Tüm mevcut UPDATE policy'lerini kaldır
DROP POLICY IF EXISTS "orders_update_seller" ON public.orders;
DROP POLICY IF EXISTS "orders_update_admin" ON public.orders;
DROP POLICY IF EXISTS "orders_update_user_cancel" ON public.orders;
DROP POLICY IF EXISTS "orders_update_unified" ON public.orders;
DROP POLICY IF EXISTS "Shop owners can update orders" ON public.orders;

-- Tek birleşik UPDATE policy oluştur
CREATE POLICY "orders_update_combined" ON public.orders
    FOR UPDATE
    TO authenticated
    USING (
        -- Satıcı: Kendi mağazasındaki siparişleri güncelleyebilir
        shop_id IN (
            SELECT id FROM public.shops 
            WHERE owner_id = (SELECT auth.uid())
        )
        OR
        -- Admin: Tüm siparişleri güncelleyebilir
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
        OR
        -- Kullanıcı: Kendi bekleyen siparişini iptal edebilir
        (user_id = (SELECT auth.uid()) AND status = 'pending')
    )
    WITH CHECK (
        -- Satıcı: Kendi mağazasındaki siparişleri güncelleyebilir
        shop_id IN (
            SELECT id FROM public.shops 
            WHERE owner_id = (SELECT auth.uid())
        )
        OR
        -- Admin: Tüm siparişleri güncelleyebilir
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
        OR
        -- Kullanıcı: Kendi bekleyen siparişini iptal edebilir
        (user_id = (SELECT auth.uid()) AND status IN ('pending', 'cancelled'))
    );

COMMENT ON POLICY "orders_update_combined" ON public.orders IS 
'Birleşik UPDATE policy: Satıcılar kendi mağaza siparişlerini, adminler tüm siparişleri, kullanıcılar bekleyen siparişlerini güncelleyebilir';

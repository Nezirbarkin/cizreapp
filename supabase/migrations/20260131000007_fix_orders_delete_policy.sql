-- Admin kullanıcıların siparişleri silebilmesi için DELETE policy'yi düzelt

-- Mevcut tüm DELETE policy'leri kaldır
DO $$
BEGIN
    DROP POLICY IF EXISTS "orders_delete_own" ON public.orders;
    DROP POLICY IF EXISTS "orders_delete_admin" ON public.orders;
    DROP POLICY IF EXISTS "orders_delete_combined" ON public.orders;
    DROP POLICY IF EXISTS "orders_delete_unified" ON public.orders;
EXCEPTION
    WHEN undefined_object THEN NULL;
END $$;

-- Admin ve kullanıcı DELETE yetkisi için birleşik policy
CREATE POLICY "orders_delete_combined" ON public.orders
    FOR DELETE TO authenticated
    USING (
        -- Admin her siparişi silebilir
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
        OR
        -- Kullanıcı kendi bekleyen siparişlerini silebilir
        (user_id = (SELECT auth.uid()) AND status = 'pending')
    );

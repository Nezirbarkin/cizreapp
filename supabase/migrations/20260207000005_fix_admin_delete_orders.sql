-- Admin panelindeki sipariş silme işlemini düzelt
-- Problem: RLS policy performansından dolayı silme başarısız olabilir

-- Eski policy'leri kaldır
DROP POLICY IF EXISTS "orders_delete_combined" ON public.orders;
DROP POLICY IF EXISTS "orders_delete_own" ON public.orders;
DROP POLICY IF EXISTS "orders_delete_admin" ON public.orders;
DROP POLICY IF EXISTS "orders_delete_unified" ON public.orders;

-- Optimize edilmiş DELETE policy
-- Admin ve kullanıcılar için ayrı koşullar, performans optimizasyonu ile
CREATE POLICY "orders_delete_optimized"
    ON public.orders
    FOR DELETE
    TO authenticated
    USING (
        -- 1. Admin kontrolü (daha verimli sorgu)
        (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin'
        OR
        -- 2. Kullanıcı sadece bekleyen siparişlerini silebilir
        (user_id = auth.uid() AND status = 'pending')
    );

-- Order items için CASCADE delete
-- Önce mevcut constraint'i kaldır
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'order_items_order_id_fkey'
        AND table_name = 'order_items'
    ) THEN
        ALTER TABLE public.order_items
        DROP CONSTRAINT order_items_order_id_fkey;
    END IF;
END $$;

-- Cascade delete ile yeniden oluştur
ALTER TABLE public.order_items
ADD CONSTRAINT order_items_order_id_fkey
FOREIGN KEY (order_id)
REFERENCES public.orders (id)
ON DELETE CASCADE
ON UPDATE CASCADE;

-- Order items DELETE policy
DROP POLICY IF EXISTS "order_items_delete" ON public.order_items;
DROP POLICY IF EXISTS "order_items_delete_policy" ON public.order_items;
DROP POLICY IF EXISTS "order_items_delete_own" ON public.order_items;

-- Order items için basitleştirilmiş policy
-- CASCADE delete sayesinde orders silindiğinde otomatik silinir
CREATE POLICY "order_items_delete_cascade"
    ON public.order_items
    FOR DELETE
    TO authenticated
    USING (
        -- Order sahibi veya admin silebilir
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = order_items.order_id
            AND (
                orders.user_id = auth.uid()
                OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin'
            )
        )
    );

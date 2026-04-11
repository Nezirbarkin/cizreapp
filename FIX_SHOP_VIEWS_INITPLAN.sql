-- ==============================================================================
-- FIX: shop_views auth_rls_initplan Uyarısı
-- ==============================================================================

-- Mevcut policy'yi sil ve düzeltilmiş versiyonunu oluştur
DROP POLICY IF EXISTS "shop_views_insert_authenticated" ON public.shop_views;

CREATE POLICY "shop_views_insert_authenticated"
    ON public.shop_views
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()) OR user_id IS NULL);

DO $$
BEGIN
    RAISE NOTICE '✅ shop_views_insert_authenticated policy düzeltildi (select auth.uid())';
END $$;

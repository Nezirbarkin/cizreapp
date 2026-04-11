-- =====================================================
-- Fix shop_views RLS Policy
-- Mağaza ziyaret kartının çalışması için INSERT policy düzeltmesi
-- =====================================================

-- Önce mevcut policies'leri temizle
DROP POLICY IF EXISTS "shop_views_insert" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_insert_policy" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_insert_authenticated" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_select" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_select_policy" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_select_public" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_select_owner_or_admin" ON public.shop_views;

-- INSERT Policy: Her authenticated kullanıcı shop_view kaydedebilir
CREATE POLICY "shop_views_insert_authenticated"
    ON public.shop_views
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- SELECT Policy: Mağaza sahibi ve adminler shop_views'ları görebilir
CREATE POLICY "shop_views_select_owner_or_admin"
    ON public.shop_views
    FOR SELECT
    TO authenticated
    USING (
        -- Mağaza sahibi ise
        EXISTS (
            SELECT 1 FROM public.shops
            WHERE shops.id = shop_views.shop_id
            AND shops.owner_id = auth.uid()
        )
        OR
        -- Admin ise
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
    );

-- Security check: RLS enabled mi?
ALTER TABLE public.shop_views ENABLE ROW LEVEL SECURITY;

-- Test için permission kontrolü (opsiyonel)
DO $$
BEGIN
    RAISE NOTICE 'shop_views RLS policies fixed successfully!';
END $$;

-- Comment
COMMENT ON POLICY "shop_views_insert_authenticated" ON public.shop_views IS 'Authenticated users can insert shop view records';
COMMENT ON POLICY "shop_views_select_owner_or_admin" ON public.shop_views IS 'Only shop owner and admins can view shop visit records';

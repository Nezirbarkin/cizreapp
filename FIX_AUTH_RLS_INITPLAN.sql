-- =====================================================
-- FIX: shop_views RLS Policy - auth.uid() initplan warning
-- =====================================================

-- Mevcut policy'i kaldır
DROP POLICY IF EXISTS "shop_views_select_owner_or_admin" ON public.shop_views;

-- Yeni policy: (select auth.uid()) kullanarak initplan sorununu çöz
CREATE POLICY "shop_views_select_owner_or_admin"
ON public.shop_views
FOR SELECT TO authenticated
USING (
    shop_id IN (
        SELECT id FROM public.shops WHERE owner_id = (select auth.uid())
    )
    OR
    EXISTS (
        SELECT 1 FROM auth.users WHERE id = (select auth.uid()) AND raw_user_meta_data->>'is_admin' = 'true'
    )
);

DO $$
BEGIN
    RAISE NOTICE '✅ shop_views RLS policy fixed with (select auth.uid())!';
END $$;

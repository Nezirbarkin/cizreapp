-- ==============================================================================
-- CLEANUP: Son kalan products anon SELECT uyarısını temizle
-- ==============================================================================

-- products_select_anon_unified ve products_select_unified birleştir
DROP POLICY IF EXISTS "products_select_anon_unified" ON public.products;
DROP POLICY IF EXISTS "products_select_unified" ON public.products;

-- Tek bir unified policy (hem anon hem authenticated için)
CREATE POLICY "products_select_unified"
ON public.products
FOR SELECT
TO public, authenticated
USING (true);

DO $$
BEGIN
    RAISE NOTICE '✅ Son policy uyarısı temizlendi';
    RAISE NOTICE '✅ products_select_unified policy oluşturuldu';
END $$;

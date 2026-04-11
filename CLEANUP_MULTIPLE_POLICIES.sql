-- ==============================================================================
-- CLEANUP: Multiple Permissive Policies Uyarılarını Temizle
-- ==============================================================================
-- Bu SQL, aynı role ve action için birden fazla policy'yi birleştirir
-- ==============================================================================

-- 1. PROFILES - Duplicate SELECT policy'leri temizle
DROP POLICY IF EXISTS "profiles_select_public" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_unified" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_public_dashboard" ON public.profiles;

-- Tek bir unified SELECT policy
CREATE POLICY "profiles_select_unified"
ON public.profiles
FOR SELECT
TO public, authenticated
USING (true);

-- 2. POSTS - Duplicate SELECT policy'leri temizle
DROP POLICY IF EXISTS "posts_select_policy" ON public.posts;
DROP POLICY IF EXISTS "posts_select_public_dashboard" ON public.posts;

-- Tek bir unified SELECT policy
CREATE POLICY "posts_select_unified"
ON public.posts
FOR SELECT
TO public, authenticated
USING (true);

-- 3. PRODUCTS - Duplicate SELECT policy'leri temizle
DROP POLICY IF EXISTS "products_select_authenticated_unified" ON public.products;
DROP POLICY IF EXISTS "products_select_public_dashboard" ON public.products;

-- Tek bir unified SELECT policy
CREATE POLICY "products_select_unified"
ON public.products
FOR SELECT
TO public, authenticated
USING (true);

-- 4. USER_REPORTS - Duplicate SELECT policy'leri temizle
DROP POLICY IF EXISTS "user_reports_select" ON public.user_reports;
DROP POLICY IF EXISTS "user_reports_select_public_dashboard" ON public.user_reports;

-- Tek bir unified SELECT policy
CREATE POLICY "user_reports_select_unified"
ON public.user_reports
FOR SELECT
TO authenticated
USING (true);

-- 5. SUPPORT_TICKETS - Duplicate SELECT policy'leri temizle
DROP POLICY IF EXISTS "support_tickets_select_optimized" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_select_authenticated_dashboard" ON public.support_tickets;

-- Tek bir unified SELECT policy
CREATE POLICY "support_tickets_select_unified"
ON public.support_tickets
FOR SELECT
TO authenticated
USING (true);

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '✅ Duplicate policy''ler temizlendi';
    RAISE NOTICE '✅ Her tablo için tek bir unified SELECT policy oluşturuldu';
    RAISE NOTICE '✅ Performance uyarıları giderildi';
END $$;

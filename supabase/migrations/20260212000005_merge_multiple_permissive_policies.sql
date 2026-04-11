-- ============================================================================
-- MULTIPLE PERMISSIVE POLICIES DÜZELT (PERFORMANCE)
-- ============================================================================
-- Sorun: Aynı role/action için birden fazla permissive policy var
--        Her query'de tüm policy'ler çalıştırılıyor (performans sorunu)
-- Çözüm: Multiple policy'leri tek bir policy olarak birleştir

-- ============================================================================
-- 1. COURIER_STATUS_CHANGES - SELECT Policy'lerini Birleştir
-- ============================================================================
-- Mevcut policy'leri kaldır
DROP POLICY IF EXISTS "courier_status_changes_admin_all" ON public.courier_status_changes;
DROP POLICY IF EXISTS "courier_status_changes_seller_select" ON public.courier_status_changes;

-- Tek bir SELECT policy oluştur (admin veya satıcı görebilir)
CREATE POLICY "courier_status_changes_select" ON public.courier_status_changes
    FOR SELECT
    TO authenticated
    USING (
        -- Admin her şeyi görebilir
        public.auth_is_admin()
        OR
        -- Satıcı sadece kendi mağazası için değişiklikleri görebilir
        EXISTS (
            SELECT 1 FROM public.shops s
            WHERE s.id = courier_status_changes.shop_id
            AND s.owner_id = (select auth.uid())
        )
    );

COMMENT ON POLICY "courier_status_changes_select" ON public.courier_status_changes IS 
'Birleştirilmiş policy: Admin veya mağaza sahibi görüntüleyebilir';

-- ============================================================================
-- 2. PRODUCT_REVIEWS - SELECT Policy'lerini Birleştir
-- ============================================================================
-- Mevcut policy'leri kaldır
DROP POLICY IF EXISTS "Herkes onaylı yorumları görebilir" ON public.product_reviews;
DROP POLICY IF EXISTS "Kullanıcılar kendi yorumlarını görebilir" ON public.product_reviews;

-- Tek bir SELECT policy oluştur (onaylı yorumlar veya kendi yorumu)
CREATE POLICY "product_reviews_select" ON public.product_reviews
    FOR SELECT
    TO authenticated
    USING (
        -- Onaylı yorumlar herkes tarafından görülebilir
        is_approved = true
        OR
        -- Kullanıcı kendi yorumlarını görebilir
        user_id = (select auth.uid())
    );

COMMENT ON POLICY "product_reviews_select" ON public.product_reviews IS 
'Birleştirilmiş policy: Onaylı yorumlar veya kendi yorumu görülebilir';

-- ============================================================================
-- 3. ANON KULLANICILAR İÇİN AYRI POLICY (Public read access)
-- ============================================================================
-- Anonim kullanıcılar için ayrı bir policy oluştur (onaylı yorumlar)
CREATE POLICY "product_reviews_select_anon" ON public.product_reviews
    FOR SELECT
    TO anon
    USING (is_approved = true);

COMMENT ON POLICY "product_reviews_select_anon" ON public.product_reviews IS 
'Anonim kullanıcılar sadece onaylı yorumları görebilir';

DO $$
BEGIN
    RAISE NOTICE '✅ Multiple permissive policies birleştirildi:';
    RAISE NOTICE '   - courier_status_changes: 2 SELECT → 1 SELECT';
    RAISE NOTICE '   - product_reviews: 2 SELECT → 2 SELECT (anon + authenticated)';
    RAISE NOTICE '';
    RAISE NOTICE '⚡ Performans iyileştirmesi uygulandı!';
    RAISE NOTICE '   Her query için artık sadece bir policy çalıştırılacak.';
END $$;

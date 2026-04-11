-- Fix Supabase Linter Warnings
-- 1. auth_rls_initplan: auth.uid() performans sorunu - (select auth.uid()) ile düzelt
-- 2. multiple_permissive_policies: Mükerrer policy'ler - birleştir
-- 3. function_search_path_mutable: Fonksiyonlara search_path ekle
-- 4. security_definer_view: SECURITY DEFINER view'ları düzelt

-- ============================================================================
-- 1. SHOPS: Multiple Permissive Policies Düzelt
-- ============================================================================

DO $$ 
BEGIN
    -- Eski policy'leri kaldır
    DROP POLICY IF EXISTS "Shop owners can update own shop" ON public.shops;
    DROP POLICY IF EXISTS "shops_update_policy" ON public.shops;
    DROP POLICY IF EXISTS "shops_delete_policy" ON public.shops;
    DROP POLICY IF EXISTS "Satıcılar kendi dükkanlarını silebilir" ON public.shops;
    DROP POLICY IF EXISTS "shops_update_unified" ON public.shops;
    DROP POLICY IF EXISTS "shops_delete_unified" ON public.shops;

    -- Yeni birleştirilmiş policy'ler oluştur (auth.uid() optimizasyonu ile)
    CREATE POLICY "shops_update_unified" ON public.shops
        FOR UPDATE
        USING (owner_id = (SELECT auth.uid()))
        WITH CHECK (owner_id = (SELECT auth.uid()));

    CREATE POLICY "shops_delete_unified" ON public.shops
        FOR DELETE
        USING (owner_id = (SELECT auth.uid()));
END $$;

-- ============================================================================
-- 2. ORDERS: Multiple Permissive Policies ve auth_rls_initplan Düzelt
-- ============================================================================

DO $$ 
BEGIN
    -- Eski policy'leri kaldır
    DROP POLICY IF EXISTS "Adminler komisyon verilerini görebilir" ON public.orders;
    DROP POLICY IF EXISTS "Satıcılar kendi komisyonunu görebilir" ON public.orders;
    DROP POLICY IF EXISTS "orders_select_unified" ON public.orders;
    DROP POLICY IF EXISTS "orders_select_optimized" ON public.orders;

    -- Yeni birleştirilmiş policy oluştur (auth.uid() optimizasyonu ile)
    CREATE POLICY "orders_select_optimized" ON public.orders
        FOR SELECT
        USING (
            user_id = (SELECT auth.uid())
            OR
            shop_id IN (
                SELECT id FROM public.shops 
                WHERE owner_id = (SELECT auth.uid())
            )
            OR
            EXISTS (
                SELECT 1 FROM public.profiles
                WHERE id = (SELECT auth.uid())
                AND role = 'admin'
            )
        );
END $$;

-- ============================================================================
-- 3. POSTS: Multiple Permissive Policies Düzelt
-- ============================================================================

DO $$ 
BEGIN
    -- Eski policy'leri kaldır
    DROP POLICY IF EXISTS "Users can create posts" ON public.posts;
    DROP POLICY IF EXISTS "posts_insert_unified" ON public.posts;
    DROP POLICY IF EXISTS "posts_insert_optimized" ON public.posts;

    -- Yeni birleştirilmiş policy oluştur
    CREATE POLICY "posts_insert_optimized" ON public.posts
        FOR INSERT
        WITH CHECK (user_id = (SELECT auth.uid()));
END $$;

-- ============================================================================
-- 4. SYSTEM_SETTINGS: auth_rls_initplan ve Multiple Policies Düzelt
-- ============================================================================

DO $$ 
BEGIN
    -- Eski policy'leri kaldır
    DROP POLICY IF EXISTS "Adminler system_settings görebilir" ON public.system_settings;
    DROP POLICY IF EXISTS "Adminler system_settings güncelleyebilir" ON public.system_settings;
    DROP POLICY IF EXISTS "system_settings_select_optimized" ON public.system_settings;
    DROP POLICY IF EXISTS "system_settings_update_optimized" ON public.system_settings;

    -- Yeni birleştirilmiş policy'ler oluştur (auth.uid() optimizasyonu ile)
    CREATE POLICY "system_settings_select_optimized" ON public.system_settings
        FOR SELECT
        USING (
            EXISTS (
                SELECT 1 FROM public.profiles
                WHERE id = (SELECT auth.uid())
                AND role = 'admin'
            )
        );

    CREATE POLICY "system_settings_update_optimized" ON public.system_settings
        FOR UPDATE
        USING (
            EXISTS (
                SELECT 1 FROM public.profiles
                WHERE id = (SELECT auth.uid())
                AND role = 'admin'
            )
        );
END $$;

-- ============================================================================
-- 5. FUNCTIONS: search_path eklenmesi (güvenlik için)
-- ============================================================================

DO $$
BEGIN
    -- Her fonksiyon için ayrı try-catch
    BEGIN
        ALTER FUNCTION public.calculate_order_commission(UUID) SET search_path = public;
    EXCEPTION WHEN OTHERS THEN
        NULL; -- Fonksiyon yoksa devam et
    END;

    BEGIN
        ALTER FUNCTION public.auto_calculate_commission() SET search_path = public;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    BEGIN
        ALTER FUNCTION public.get_admin_commission_report() SET search_path = public;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    BEGIN
        ALTER FUNCTION public.get_seller_commission_summary(UUID) SET search_path = public;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    BEGIN
        ALTER FUNCTION public.update_system_settings_updated_at() SET search_path = public;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
END $$;

-- ============================================================================
-- 6. VIEWS: SECURITY DEFINER sorunlarını düzelt
-- View'ları SECURITY INVOKER olarak yeniden oluştur
-- ============================================================================

-- View'ları güvenli hale getir (sadece security_invoker ekle, kolonları değiştirme)
DO $$
BEGIN
    -- v_admin_commission_dashboard view'ını güvenli hale getir
    ALTER VIEW public.v_admin_commission_dashboard SET (security_invoker = true);
    
    -- v_debt_orders view'ını güvenli hale getir
    ALTER VIEW public.v_debt_orders SET (security_invoker = true);
EXCEPTION WHEN OTHERS THEN
    -- View'lar yoksa veya alter edilemiyorsa devam et
    RAISE NOTICE 'View güvenlik ayarlaması atlandı: %', SQLERRM;
END $$;

-- View'lar için erişim izinleri
GRANT SELECT ON public.v_admin_commission_dashboard TO authenticated;
GRANT SELECT ON public.v_debt_orders TO authenticated;

-- ============================================================================
-- Bilgilendirme
-- ============================================================================

COMMENT ON POLICY "shops_update_unified" ON public.shops IS 
'Optimized: Satıcılar kendi dükkanlarını güncelleyebilir. auth.uid() SELECT ile optimize edildi.';

COMMENT ON POLICY "shops_delete_unified" ON public.shops IS 
'Optimized: Satıcılar kendi dükkanlarını silebilir. auth.uid() SELECT ile optimize edildi.';

COMMENT ON POLICY "orders_select_optimized" ON public.orders IS 
'Optimized: Kullanıcılar kendi siparişlerini, satıcılar kendi dükkan siparişlerini, adminler tüm siparişleri görebilir. Mükerrer policy birleştirildi ve auth.uid() optimize edildi.';

COMMENT ON POLICY "posts_insert_optimized" ON public.posts IS 
'Optimized: Kullanıcılar post oluşturabilir. Mükerrer policy birleştirildi.';

COMMENT ON POLICY "system_settings_select_optimized" ON public.system_settings IS 
'Optimized: Adminler sistem ayarlarını görebilir. auth.uid() SELECT ile optimize edildi.';

COMMENT ON POLICY "system_settings_update_optimized" ON public.system_settings IS 
'Optimized: Adminler sistem ayarlarını güncelleyebilir. auth.uid() SELECT ile optimize edildi.';

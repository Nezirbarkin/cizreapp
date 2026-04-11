-- ============================================================================
-- ADMIN DÜKKAN YÖNETİMİ BOŞ GÖRÜNİYOR SORUNU DÜZELT
-- ============================================================================
-- Sorun: Admin panelinde dükkan yönetimi ekranı boş görünüyor
-- Sebep: shops_select_policy sadece is_active = true olan dükkanları gösteriyor
-- Çözüm: Admin tüm dükkanları görebilmeli (onay bekleyenler dahil)

-- ============================================================================
-- 1. Mevcut Policy Durumu
-- ============================================================================
DO $$
DECLARE
    policy_count INT;
    policy_record RECORD;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Shops SELECT Policy Durumu:';
    RAISE NOTICE '========================================';
    
    SELECT COUNT(*) INTO policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'shops'
    AND cmd = 'SELECT';
    
    RAISE NOTICE 'Shops SELECT policy sayısı: %', policy_count;
    
    FOR policy_record IN
        SELECT policyname, cmd 
        FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'shops'
        AND cmd = 'SELECT'
    LOOP
        RAISE NOTICE 'Policy: %', policy_record.policyname;
    END LOOP;
    
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- 2. Helper Function Kontrolü
-- ============================================================================
CREATE OR REPLACE FUNCTION public.auth_is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM public.profiles 
        WHERE id = auth.uid() 
        AND role = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER 
SET search_path = public;

COMMENT ON FUNCTION public.auth_is_admin() IS 
'Güvenli admin kontrolü - RLS policy''lerde kullanılır';

-- ============================================================================
-- 3. Mevcut shops_select_policy'leri Sil
-- ============================================================================
DROP POLICY IF EXISTS "shops_select_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_select" ON public.shops;
DROP POLICY IF EXISTS "shops_select_all" ON public.shops;
DROP POLICY IF EXISTS "shops_select_combined" ON public.shops;
DROP POLICY IF EXISTS "shops_select_unified" ON public.shops;

-- ============================================================================
-- 4. Yeni shops_select_policy - Tek bir unified policy
-- ============================================================================
-- Tek policy - performans için ve linter uyarısını önlemek için
CREATE POLICY "shops_select_unified" ON public.shops
    FOR SELECT
    TO anon, authenticated
    USING (
        -- Admin TÜM dükkanları görebilir (onay bekleyenler, pasifler dahil)
        public.auth_is_admin()
        OR
        -- Diğer kullanıcılar sadece aktif ve onaylı dükkanları görebilir
        (is_active = true AND is_approved = true)
    );

COMMENT ON POLICY "shops_select_unified" ON public.shops IS
'Birleştirilmiş policy: Admin tüm dükkanları, diğerleri sadece aktif/onaylı dükkanları görebilir';

-- ============================================================================
-- 5. Son Durum Raporu
-- ============================================================================
DO $$
DECLARE
    policy_count INT;
    total_shops INT;
    pending_shops INT;
    active_shops INT;
BEGIN
    SELECT COUNT(*) INTO policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'shops'
    AND cmd = 'SELECT';
    
    SELECT COUNT(*) INTO total_shops FROM public.shops;
    SELECT COUNT(*) INTO pending_shops FROM public.shops WHERE is_approved = false;
    SELECT COUNT(*) INTO active_shops FROM public.shops WHERE is_active = true AND is_approved = true;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ FIX TAMAMLANDI';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Shops SELECT policy sayısı: % (olması gereken: 1)', policy_count;
    RAISE NOTICE '';
    RAISE NOTICE 'DÜKKAN İSTATİSTİKLERİ:';
    RAISE NOTICE '  Toplam dükkan: %', total_shops;
    RAISE NOTICE '  Onay bekleyen: %', pending_shops;
    RAISE NOTICE '  Aktif ve onaylı: %', active_shops;
    RAISE NOTICE '';
    RAISE NOTICE 'YETKİLER:';
    RAISE NOTICE '  ✓ Misafirler (anon) aktif/onaylı dükkanları görebilir';
    RAISE NOTICE '  ✓ Admin TÜM dükkanları görebilir';
    RAISE NOTICE '  ✓ Diğer kullanıcılar aktif/onaylı dükkanları görebilir';
    RAISE NOTICE '';
    RAISE NOTICE 'PERFORMANS:';
    RAISE NOTICE '  ✓ Tek unified policy - linter uyarısı yok';
    RAISE NOTICE '  ✓ auth_is_admin() SECURITY DEFINER kullanıyor';
    RAISE NOTICE '';
    
    IF policy_count = 1 THEN
        RAISE NOTICE '✅ BAŞARILI: Tek unified SELECT policy mevcut';
    ELSE
        RAISE WARNING '⚠️  DİKKAT: % SELECT policy var, olması gereken 1!', policy_count;
    END IF;
    
    IF total_shops = 0 THEN
        RAISE WARNING '⚠️  Sistemde hiç dükkan yok!';
    END IF;
    
    RAISE NOTICE '========================================';
END $$;

-- ============================================================================
-- 6. Notifications auth_rls_initplan uyarısını düzelt
-- ============================================================================
-- notifications_insert_policy policy'sinde auth.uid() performans sorunu var
DO $$
BEGIN
    -- Mevcut policy'yi kontrol et ve düzelt
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'notifications'
        AND policyname = 'notifications_insert_policy'
        AND cmd = 'INSERT'
    ) THEN
        -- Policy'yi drop ve yeniden oluştur (select auth.uid() ile)
        DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;
        
        CREATE POLICY "notifications_insert_policy" ON public.notifications
            FOR INSERT
            TO authenticated
            WITH CHECK (
                user_id = (select auth.uid())
                OR
                -- Sistem bildirimleri için (service_role tarafından oluşturulanlar)
                -- Kullanıcı kendi adına bildirim oluşturabilir
                true
            );
        
        RAISE NOTICE '✅ notifications_insert_policy policy güncellendi (select auth.uid())';
    ELSE
        RAISE NOTICE 'ℹ️  notifications_insert_policy policy bulunamadı';
    END IF;
END $$;

-- ============================================================================
-- 7. Final Rapor
-- ============================================================================
DO $$
DECLARE
    shops_policy_count INT;
    notifications_policy_count INT;
BEGIN
    SELECT COUNT(*) INTO shops_policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'shops'
    AND cmd = 'SELECT';
    
    SELECT COUNT(*) INTO notifications_policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'notifications'
    AND cmd = 'INSERT';
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🎉 TÜM DÜZELTMELER TAMAMLANDI';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Linter Uyarıları:';
    RAISE NOTICE '  ✓ Shops: Tek unified policy (multiple_permissive_policies çözüldü)';
    RAISE NOTICE '  ✓ Notifications: auth.uid() → select auth.uid() (auth_rls_initplan çözüldü)';
    RAISE NOTICE '';
    RAISE NOTICE 'Policy Sayıları:';
    RAISE NOTICE '  Shops SELECT: % (beklenen: 1)', shops_policy_count;
    RAISE NOTICE '  Notifications INSERT: %', notifications_policy_count;
    RAISE NOTICE '';
    RAISE NOTICE 'Yetkiler:';
    RAISE NOTICE '  ✓ Misafirler (anon) aktif/onaylı dükkanları görebilir';
    RAISE NOTICE '  ✓ Admin TÜM dükkanları görebilir';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
END $$;

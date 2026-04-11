-- ==============================================================================
-- FIX: Admin Dashboard Permission Denied Hatası (GÜVENLİ VERSİYON)
-- ==============================================================================
-- Hata: PostgrestException(message: permission denied for table users, code: 42501)
-- Çözüm: Mevcut policy'leri kontrol et ve sadece sorunlu olanları düzelt
-- ==============================================================================

-- Önce mevcut policy'leri görüntüle
SELECT 
    tablename,
    policyname,
    cmd,
    permissive,
    roles
FROM pg_policies 
WHERE tablename IN ('profiles', 'posts', 'products', 'orders', 'user_reports', 'support_tickets')
ORDER BY tablename, policyname;

-- ==============================================================================
-- 1. AUTH.USERS ERİŞİMİ OLAN POLICY'LERİ BUL VE DÜZELT
-- ==============================================================================

-- Profiles tablosu için - auth.users içeren policy'leri sil
DO $$
DECLARE
    policy_rec RECORD;
BEGIN
    FOR policy_rec IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'profiles' 
        AND (qual ILIKE '%auth.users%' OR with_check ILIKE '%auth.users%')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.profiles', policy_rec.policyname);
        RAISE NOTICE 'Dropped policy: %', policy_rec.policyname;
    END LOOP;
END $$;

-- Posts tablosu için - auth.users içeren policy'leri sil
DO $$
DECLARE
    policy_rec RECORD;
BEGIN
    FOR policy_rec IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'posts' 
        AND (qual ILIKE '%auth.users%' OR with_check ILIKE '%auth.users%')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.posts', policy_rec.policyname);
        RAISE NOTICE 'Dropped policy: %', policy_rec.policyname;
    END LOOP;
END $$;

-- Products tablosu için - auth.users içeren policy'leri sil
DO $$
DECLARE
    policy_rec RECORD;
BEGIN
    FOR policy_rec IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'products' 
        AND (qual ILIKE '%auth.users%' OR with_check ILIKE '%auth.users%')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.products', policy_rec.policyname);
        RAISE NOTICE 'Dropped policy: %', policy_rec.policyname;
    END LOOP;
END $$;

-- Orders tablosu için - auth.users içeren policy'leri sil
DO $$
DECLARE
    policy_rec RECORD;
BEGIN
    FOR policy_rec IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'orders' 
        AND (qual ILIKE '%auth.users%' OR with_check ILIKE '%auth.users%')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.orders', policy_rec.policyname);
        RAISE NOTICE 'Dropped policy: %', policy_rec.policyname;
    END LOOP;
END $$;

-- User_reports tablosu için - auth.users içeren policy'leri sil
DO $$
DECLARE
    policy_rec RECORD;
BEGIN
    FOR policy_rec IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'user_reports' 
        AND (qual ILIKE '%auth.users%' OR with_check ILIKE '%auth.users%')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.user_reports', policy_rec.policyname);
        RAISE NOTICE 'Dropped policy: %', policy_rec.policyname;
    END LOOP;
END $$;

-- Support_tickets tablosu için - auth.users içeren policy'leri sil
DO $$
DECLARE
    policy_rec RECORD;
BEGIN
    FOR policy_rec IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'support_tickets' 
        AND (qual ILIKE '%auth.users%' OR with_check ILIKE '%auth.users%')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.support_tickets', policy_rec.policyname);
        RAISE NOTICE 'Dropped policy: %', policy_rec.policyname;
    END LOOP;
END $$;

-- ==============================================================================
-- 2. HER TABLO İÇİN SEÇİLİ SELECT POLICY OLUŞTUR (YOKSA)
-- ==============================================================================

-- Profiles için SELECT policy oluştur (yoksa)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'profiles' 
        AND policyname = 'profiles_select_public_dashboard'
        AND cmd = 'SELECT'
    ) THEN
        CREATE POLICY "profiles_select_public_dashboard"
        ON public.profiles
        FOR SELECT
        TO authenticated
        USING (true);
        RAISE NOTICE '✅ Created profiles_select_public_dashboard';
    ELSE
        RAISE NOTICE 'ℹ️ profiles_select_public_dashboard already exists';
    END IF;
END $$;

-- Posts için SELECT policy oluştur (yoksa)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'posts' 
        AND policyname = 'posts_select_public_dashboard'
        AND cmd = 'SELECT'
    ) THEN
        CREATE POLICY "posts_select_public_dashboard"
        ON public.posts
        FOR SELECT
        TO authenticated
        USING (true);
        RAISE NOTICE '✅ Created posts_select_public_dashboard';
    ELSE
        RAISE NOTICE 'ℹ️ posts_select_public_dashboard already exists';
    END IF;
END $$;

-- Products için SELECT policy oluştur (yoksa)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'products' 
        AND policyname = 'products_select_public_dashboard'
        AND cmd = 'SELECT'
    ) THEN
        CREATE POLICY "products_select_public_dashboard"
        ON public.products
        FOR SELECT
        TO authenticated
        USING (true);
        RAISE NOTICE '✅ Created products_select_public_dashboard';
    ELSE
        RAISE NOTICE 'ℹ️ products_select_public_dashboard already exists';
    END IF;
END $$;

-- Orders için SELECT policy oluştur (yoksa)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'orders' 
        AND policyname = 'orders_select_public_dashboard'
        AND cmd = 'SELECT'
    ) THEN
        CREATE POLICY "orders_select_public_dashboard"
        ON public.orders
        FOR SELECT
        TO authenticated
        USING (true);
        RAISE NOTICE '✅ Created orders_select_public_dashboard';
    ELSE
        RAISE NOTICE 'ℹ️ orders_select_public_dashboard already exists';
    END IF;
END $$;

-- User_reports için SELECT policy oluştur (yoksa)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'user_reports' 
        AND policyname = 'user_reports_select_public_dashboard'
        AND cmd = 'SELECT'
    ) THEN
        CREATE POLICY "user_reports_select_public_dashboard"
        ON public.user_reports
        FOR SELECT
        TO authenticated
        USING (true);
        RAISE NOTICE '✅ Created user_reports_select_public_dashboard';
    ELSE
        RAISE NOTICE 'ℹ️ user_reports_select_public_dashboard already exists';
    END IF;
END $$;

-- Support_tickets için SELECT policy oluştur (yoksa)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'support_tickets' 
        AND policyname = 'support_tickets_select_authenticated_dashboard'
        AND cmd = 'SELECT'
    ) THEN
        CREATE POLICY "support_tickets_select_authenticated_dashboard"
        ON public.support_tickets
        FOR SELECT
        TO authenticated
        USING (true);
        RAISE NOTICE '✅ Created support_tickets_select_authenticated_dashboard';
    ELSE
        RAISE NOTICE 'ℹ️ support_tickets_select_authenticated_dashboard already exists';
    END IF;
END $$;

-- ==============================================================================
-- 3. SON KONTROL
-- ==============================================================================

DO $$
DECLARE
    v_profiles_select INTEGER;
    v_posts_select INTEGER;
    v_products_select INTEGER;
    v_orders_select INTEGER;
    v_reports_select INTEGER;
    v_tickets_select INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_profiles_select FROM pg_policies WHERE tablename = 'profiles' AND cmd = 'SELECT';
    SELECT COUNT(*) INTO v_posts_select FROM pg_policies WHERE tablename = 'posts' AND cmd = 'SELECT';
    SELECT COUNT(*) INTO v_products_select FROM pg_policies WHERE tablename = 'products' AND cmd = 'SELECT';
    SELECT COUNT(*) INTO v_orders_select FROM pg_policies WHERE tablename = 'orders' AND cmd = 'SELECT';
    SELECT COUNT(*) INTO v_reports_select FROM pg_policies WHERE tablename = 'user_reports' AND cmd = 'SELECT';
    SELECT COUNT(*) INTO v_tickets_select FROM pg_policies WHERE tablename = 'support_tickets' AND cmd = 'SELECT';
    
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '✅ DASHBOARD PERMISSION DÜZELTMESİ TAMAMLANDI';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '📊 Tablo Policy Durumları:';
    RAISE NOTICE '   profiles:    % SELECT policies', v_profiles_select;
    RAISE NOTICE '   posts:       % SELECT policies', v_posts_select;
    RAISE NOTICE '   products:    % SELECT policies', v_products_select;
    RAISE NOTICE '   orders:      % SELECT policies', v_orders_select;
    RAISE NOTICE '   user_reports: % SELECT policies', v_reports_select;
    RAISE NOTICE '   support_tickets: % SELECT policies', v_tickets_select;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '✅ auth.users içeren policy''ler temizlendi';
    RAISE NOTICE '✅ Dashboard için SELECT policy''leri eklendi';
    RAISE NOTICE '✅ Uygulamayı yeniden başlatıp test edin';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
END $$;

-- Mevcut policy'leri tekrar göster
SELECT 
    tablename,
    policyname,
    cmd,
    roles
FROM pg_policies 
WHERE tablename IN ('profiles', 'posts', 'products', 'orders', 'user_reports', 'support_tickets')
ORDER BY tablename, cmd, policyname;

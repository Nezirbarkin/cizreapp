-- ============================================================================
-- ADMIN ROL DEĞİŞTİRME SORUNU DÜZELT - GÜVENLI VERSİYON
-- ============================================================================
-- Sorun: Admin panelinde kullanıcı rolü değiştirildiğinde değişiklik yansımıyor
-- Sebep: profiles_update_own policy'si admin kontrolü içermiyor
-- Çözüm: Mevcut is_admin() fonksiyonunu kullanarak UPDATE policy'sini güncelle

-- ============================================================================
-- 1. Mevcut Durumu Kontrol Et
-- ============================================================================
DO $$
DECLARE
    policy_record RECORD;
    has_is_admin_func BOOLEAN;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Mevcut Profiles UPDATE Policy Durumu:';
    RAISE NOTICE '========================================';
    
    -- Mevcut policy'leri listele
    FOR policy_record IN
        SELECT policyname, cmd 
        FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'profiles'
        AND cmd = 'UPDATE'
    LOOP
        RAISE NOTICE 'Policy: % (%)', policy_record.policyname, policy_record.cmd;
    END LOOP;
    
    -- is_admin fonksiyonu var mı?
    SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'is_admin' 
        AND pronamespace = 'public'::regnamespace
    ) INTO has_is_admin_func;
    
    IF has_is_admin_func THEN
        RAISE NOTICE '✅ is_admin() fonksiyonu mevcut';
    ELSE
        RAISE NOTICE '⚠️  is_admin() fonksiyonu bulunamadı - oluşturulacak';
    END IF;
    
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- 2. is_admin() Fonksiyonunu Kontrol Et / Oluştur
-- ============================================================================
-- Bu fonksiyon zaten 20260209000002 migration'ında oluşturulmuş olmalı
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
    RETURN v_role = 'admin';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER 
SET search_path = public;

COMMENT ON FUNCTION public.is_admin() IS 
'Güvenli admin kontrolü - mevcut kullanıcının admin olup olmadığını kontrol eder';

-- ============================================================================
-- 3. profiles_update_own Policy'sini Güncelle (Admin Desteği Ekle)
-- ============================================================================
-- Mevcut policy'yi sil ve admin desteği ile yeniden oluştur
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own" ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (
        -- Kullanıcı kendi profilini güncelleyebilir
        id = (select auth.uid())
        OR
        -- Admin tüm profilleri güncelleyebilir
        public.is_admin()
    )
    WITH CHECK (
        -- Kullanıcı kendi profilini güncelleyebilir
        id = (select auth.uid())
        OR
        -- Admin tüm profilleri güncelleyebilir
        public.is_admin()
    );

COMMENT ON POLICY "profiles_update_own" ON public.profiles IS 
'Kullanıcı kendi profilini veya admin tüm profilleri güncelleyebilir (GÜNCELLENDİ)';

-- ============================================================================
-- 4. Diğer Çakışan Policy'leri Temizle (Güvenlik için)
-- ============================================================================
-- Eğer başka UPDATE policy'leri varsa, onları da sil
DROP POLICY IF EXISTS "profiles_update_policy" ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_update" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_unified" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Enable update for users based on id" ON public.profiles;

-- ============================================================================
-- 5. Doğrulama ve Rapor
-- ============================================================================
DO $$
DECLARE
    update_policy_count INT;
    admin_count INT;
    rls_enabled BOOLEAN;
BEGIN
    -- Policy sayısını kontrol et
    SELECT COUNT(*) INTO update_policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'profiles'
    AND cmd = 'UPDATE';
    
    -- Admin sayısını kontrol et
    SELECT COUNT(*) INTO admin_count 
    FROM public.profiles 
    WHERE role = 'admin';
    
    -- RLS aktif mi?
    SELECT relrowsecurity INTO rls_enabled
    FROM pg_class
    WHERE oid = 'public.profiles'::regclass;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ FIX TAMAMLANDI';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Profiles UPDATE policy sayısı: % (olması gereken: 1)', update_policy_count;
    RAISE NOTICE 'RLS durumu: %', CASE WHEN rls_enabled THEN 'Aktif ✅' ELSE 'Kapalı ⚠️' END;
    RAISE NOTICE 'Sistemdeki admin sayısı: %', admin_count;
    RAISE NOTICE '';
    RAISE NOTICE 'YAPILAN DEĞİŞİKLİKLER:';
    RAISE NOTICE '  ✓ is_admin() fonksiyonu kontrol edildi/oluşturuldu';
    RAISE NOTICE '  ✓ profiles_update_own policy güncellendi (admin desteği eklendi)';
    RAISE NOTICE '  ✓ Çakışan diğer UPDATE policy''leri temizlendi';
    RAISE NOTICE '';
    RAISE NOTICE 'YENİ YETKİLER:';
    RAISE NOTICE '  ✓ Kullanıcılar kendi profillerini güncelleyebilir';
    RAISE NOTICE '  ✓ Adminler TÜM profilleri güncelleyebilir';
    RAISE NOTICE '  ✓ Adminler kullanıcı rollerini değiştirebilir';
    RAISE NOTICE '';
    
    IF update_policy_count = 1 THEN
        RAISE NOTICE '✅ BAŞARILI: Tek bir UPDATE policy mevcut';
    ELSE
        RAISE WARNING '⚠️  DİKKAT: % UPDATE policy var, olması gereken 1!', update_policy_count;
    END IF;
    
    IF admin_count > 0 THEN
        RAISE NOTICE '✅ Sistemde % admin kullanıcı mevcut', admin_count;
    ELSE
        RAISE WARNING '⚠️  Sistemde admin kullanıcı yok!';
    END IF;
    
    IF NOT rls_enabled THEN
        RAISE WARNING '⚠️  RLS KAPALI! Güvenlik riski var!';
    END IF;
    
    RAISE NOTICE '';
    RAISE NOTICE 'TEST İÇİN:';
    RAISE NOTICE '  1. Admin paneline giriş yapın';
    RAISE NOTICE '  2. Kullanıcı Yönetimi → Bir kullanıcının rolünü değiştirin';
    RAISE NOTICE '  3. Değişikliğin anında yansıdığını kontrol edin';
    RAISE NOTICE '========================================';
END $$;

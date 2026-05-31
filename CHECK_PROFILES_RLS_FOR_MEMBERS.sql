-- ================================================
-- profiles tablosu RLS politikalarını kontrol et
-- ================================================

-- 1. Mevcut profiles politikalarını listele
SELECT 
    policyname, 
    cmd, 
    qual::text as using_clause,
    with_check::text as with_check_clause
FROM pg_policies 
WHERE tablename = 'profiles' 
ORDER BY cmd, policyname;

-- 2. RLS durumunu kontrol et
SELECT 
    relname, 
    relrowsecurity as rls_enabled,
    relforce_rowsec as rls_forced
FROM pg_class 
WHERE relname = 'profiles';

-- 3. Anon rolünün profillere erişimini test et
-- Bu sorguyu Supabase Dashboard'da SQL Editor'de çalıştır
SELECT 
    id, 
    username, 
    full_name, 
    created_at,
    is_ghost_mode
FROM profiles 
LIMIT 50;

-- 4. Yeni kullanıcıların olup olmadığını kontrol et
SELECT 
    COUNT(*) as total_profiles,
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') as new_profiles_last_week,
    MAX(created_at) as last_profile_created
FROM profiles;

-- ================================================
-- Eğer yukarıdaki sorgular sorun göstermiyorsa,
-- aşağıdaki düzeltmeleri uygula:
-- ================================================

-- profiles tablosu için tüm politikaları temizle ve yeniden oluştur
-- Bu komutları dikkatli kullan!

-- 1. Mevcut policies'i sil
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'profiles' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.profiles', policy_policy.policyname);
    END LOOP;
END $$;

-- 2. SELECT policy - Herkes profilleri görebilir
CREATE POLICY "profiles_select_all" ON public.profiles
    FOR SELECT USING (true);

-- 3. INSERT policy - Kullanıcılar kendi profillerini oluşturabilir
CREATE POLICY "profiles_insert_own" ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

-- 4. UPDATE policy - Kullanıcılar kendi profillerini güncelleyebilir
CREATE POLICY "profiles_update_own" ON public.profiles
    FOR UPDATE USING (auth.uid() = id);

-- 5. Admin için ek UPDATE policy
CREATE POLICY "profiles_admin_update" ON public.profiles
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- 6. DELETE policy - Admin profilleri silebilir
CREATE POLICY "profiles_admin_delete" ON public.profiles
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

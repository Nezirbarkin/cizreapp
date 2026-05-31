-- ================================================
-- profiles tablosu RLS politikalarını düzelt
-- Bu dosya yeni kullanıcıların "Arkadaş ekle" ekranında görünmesini sağlar
-- ================================================

-- 1. Tüm mevcut profiles politikalarını sil
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'profiles' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.profiles', policy_record.policyname);
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

-- 7. Test: Tüm profilleri listele
SELECT id, username, full_name, created_at, is_ghost_mode 
FROM profiles 
ORDER BY created_at DESC 
LIMIT 20;

-- ============================================================================
-- FIX: profiles tablosu permission denied for table users hatası
-- ============================================================================
-- Sorun: profiles tablosunun SELECT policy'si auth.users'a erişmeye çalışıyor
-- Çözüm: profiles RLS policy'lerini düzelt

-- 1. Mevcut profiles policy'lerini kontrol et
SELECT 
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'profiles'
ORDER BY policyname;

-- 2. profiles SELECT policy'ini düzelt (auth.users kullanımını kaldır)
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_authenticated_select_policy" ON public.profiles;
DROP POLICY IF EXISTS "profiles_public_select_policy" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_delete_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_all" ON public.profiles;

-- 3. Temiz policy'ler oluştur
CREATE POLICY "profiles_select_own"
ON public.profiles
FOR SELECT
TO authenticated
USING (id = auth.uid());

CREATE POLICY "profiles_select_public"
ON public.profiles
FOR SELECT
TO public, authenticated
USING (true);  -- Herkes profilleri görebilir

CREATE POLICY "profiles_insert_own"
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_update_own"
ON public.profiles
FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- 4. Kontrol
DO $$
BEGIN
    RAISE NOTICE '✅ Profiles policy''leri d��zeltildi';
    RAISE NOTICE '✅ auth.users erişimi kaldırıldı';
END $$;

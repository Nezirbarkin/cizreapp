-- ================================================
-- profiles tablosu RLS politikalarını kontrol et
-- Sadece kontrol eder, hiçbir şeyi değiştirmez
-- ================================================

-- 1. Mevcut profiles politikalarını listele
SELECT 
    policyname, 
    cmd, 
    qual::text as using_clause
FROM pg_policies 
WHERE tablename = 'profiles' 
ORDER BY cmd, policyname;

-- 2. RLS durumunu kontrol et
SELECT 
    relname, 
    relrowsecurity as rls_enabled
FROM pg_class 
WHERE relname = 'profiles';

-- 3. Anon kullanıcının erişimini test et (supabaseAnonKey ile)
SELECT 
    COUNT(*) as toplam_profil,
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') as son_7_gunde_eklenen
FROM profiles;

-- 4. Son eklenen 10 kullanıcı
SELECT 
    id, 
    username, 
    full_name, 
    created_at,
    is_ghost_mode
FROM profiles 
ORDER BY created_at DESC 
LIMIT 10;

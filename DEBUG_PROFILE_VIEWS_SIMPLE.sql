-- ============================================
-- PROFILE VIEWS SIMPLEST DEBUG SCRIPT
-- Bu scripti parça parça çalıştırın
-- ============================================

-- 1. TABLO YAPISI KONTROL
SELECT '1. TABLO YAPISI' as step;
SELECT table_name FROM information_schema.tables 
WHERE table_name IN ('profile_views', 'post_views');

-- 2. PROFILE_VIEWS TABLOSUNDA KAÇ KAYIT VAR?
SELECT '2. PROFILE_VIEWS KAYIT SAYISI' as step;
SELECT COUNT(*) as kayit_sayisi FROM profile_views;

-- 3. POST_VIEWS TABLOSUNDA KAÇ KAYIT VAR?
SELECT '3. POST_VIEWS KAYIT SAYISI' as step;
SELECT COUNT(*) as kayit_sayisi FROM post_views;

-- 4. SON 5 PROFILE VIEW KAYDINI GÖR
SELECT '4. SON 5 PROFILE VIEW' as step;
SELECT 
    id,
    profile_id,
    viewer_id,
    viewed_at,
    view_date
FROM profile_views
ORDER BY viewed_at DESC
LIMIT 5;

-- 5. FONKSİYONLAR VAR MI?
SELECT '5. FONKSIYONLAR' as step;
SELECT routine_name FROM information_schema.routines 
WHERE routine_name LIKE 'track_%' OR routine_name LIKE 'get_%profile%'
ORDER BY routine_name;

-- 6. BUGÜNÜN GÖRÜNTÜLEMELERI
SELECT '6. BUGÜNÜN GÖRÜNTÜLEMELERI' as step;
SELECT 
    COUNT(*) as total_today,
    COUNT(DISTINCT viewer_id) as unique_viewers_today
FROM profile_views
WHERE view_date = CURRENT_DATE;

-- 7. PROFILE_VIEWS CONTRAINT'LERI
SELECT '7. CONSTRAINTS' as step;
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_name = 'profile_views';

-- 8. CURRENT USER
SELECT '8. MEVCUT KULLANICI' as step;
SELECT auth.uid() as current_user;

-- 9. KAÇ PROFIL VAR?
SELECT '9. PROFIL SAYISI' as step;
SELECT COUNT(*) as profil_sayisi FROM profiles;

-- 10. RLS ENABLED MI?
SELECT '10. RLS DURUMU' as step;
SELECT 
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename IN ('profile_views', 'post_views');

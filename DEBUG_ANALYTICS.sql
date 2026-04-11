-- ================================================
-- ANALYTICS DEBUG - Profil Ziyaretlerini Kontrol Et
-- ================================================

-- 1. Tablolar var mı?
SELECT 
    tablename,
    schemaname
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('profile_views', 'post_views');

-- 2. Fonksiyonlar var mı?
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name IN ('track_profile_view', 'track_post_view', 'get_profile_current_month_views', 'get_user_current_month_post_views');

-- 3. profile_views tablosunda veri var mı?
SELECT 
    pv.id,
    pv.profile_id,
    pv.viewer_id,
    pv.viewed_at,
    pv.view_date,
    p1.username as profile_username,
    p2.username as viewer_username
FROM profile_views pv
LEFT JOIN profiles p1 ON p1.id = pv.profile_id
LEFT JOIN profiles p2 ON p2.id = pv.viewer_id
ORDER BY pv.viewed_at DESC
LIMIT 20;

-- 4. post_views tablosunda veri var mı?
SELECT 
    pv.id,
    pv.post_id,
    pv.viewer_id,
    pv.viewed_at,
    pv.view_date,
    p.username as viewer_username
FROM post_views pv
LEFT JOIN profiles p ON p.id = pv.viewer_id
ORDER BY pv.viewed_at DESC
LIMIT 20;

-- 5. Manuel test - fonksiyonu çağır
-- ÖNEMLI: Kendi user_id'nizi buraya yazın
DO $$
DECLARE
    test_user_id uuid := auth.uid();
    test_stats record;
BEGIN
    RAISE NOTICE 'Test user ID: %', test_user_id;
    
    -- Profil görüntüleme ekle
    PERFORM track_profile_view(test_user_id);
    RAISE NOTICE 'Profil görüntüleme eklendi';
    
    -- İstatistikleri getir
    SELECT * INTO test_stats FROM get_profile_current_month_views(test_user_id);
    RAISE NOTICE 'Profil stats - total_views: %, unique_viewers: %', 
        test_stats.total_views, test_stats.unique_viewers;
        
    SELECT * INTO test_stats FROM get_user_current_month_post_views(test_user_id);
    RAISE NOTICE 'Post stats - total_views: %, unique_viewers: %', 
        test_stats.total_views, test_stats.unique_viewers;
END $$;

-- 6. RLS Policies kontrol et
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies 
WHERE tablename IN ('profile_views', 'post_views')
ORDER BY tablename, policyname;

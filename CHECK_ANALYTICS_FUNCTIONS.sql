-- Analytics fonksiyonlarını test et

-- 1. Tablolar var mı kontrol et
SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'profile_views'
) as profile_views_exists;

SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'post_views'
) as post_views_exists;

-- 2. Fonksiyonlar var mı kontrol et
SELECT routine_name, routine_type 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name IN ('track_profile_view', 'get_profile_current_month_views', 'get_user_current_month_post_views');

-- 3. Kendi user_id'nizi buraya yazın ve test edin
-- ÖNEMLI: Aşağıdaki 'YOUR_USER_ID_HERE' yerine kendi kullanıcı ID'nizi yazın
DO $$
DECLARE
    test_user_id uuid := auth.uid(); -- Otomatik olarak giriş yapmış kullanıcının ID'sini alır
BEGIN
    RAISE NOTICE 'Test kullanıcı ID: %', test_user_id;
    
    -- Profil görüntüleme kaydet
    PERFORM track_profile_view(test_user_id);
    RAISE NOTICE 'Profil görüntüleme kaydedildi';
    
    -- İstatistikleri getir
    RAISE NOTICE 'Profil istatistikleri: %', (SELECT row_to_json(t) FROM get_profile_current_month_views(test_user_id) t);
    RAISE NOTICE 'Post istatistikleri: %', (SELECT row_to_json(t) FROM get_user_current_month_post_views(test_user_id) t);
END $$;

-- 4. Manuel test - kendi user_id'nizi aşağıya yazın
-- SELECT * FROM get_profile_current_month_views('YOUR_USER_ID_HERE');
-- SELECT * FROM get_user_current_month_post_views('YOUR_USER_ID_HERE');

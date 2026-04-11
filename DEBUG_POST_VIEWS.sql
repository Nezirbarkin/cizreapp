-- POST GÖRÜNTÜLEME DEBUG
-- Bu scripti Supabase SQL Editor'da çalıştırın

-- 1. POST_VIEWS TABLOSUNDA KAÇ KAYIT VAR?
SELECT '1. POST_VIEWS KAYIT SAYISI' as step;
SELECT COUNT(*) as total_records FROM post_views;

-- 2. BUGÜNÜN POST GÖRÜNTÜLEMELERI
SELECT '2. BUGÜNKÜ GÖRÜNTÜLEMELER' as step;
SELECT 
    COUNT(*) as today_views,
    COUNT(DISTINCT viewer_id) as unique_viewers
FROM post_views
WHERE view_date = CURRENT_DATE;

-- 3. SON 5 POST VIEW KAYDINI GÖR
SELECT '3. SON 5 POST VIEW' as step;
SELECT 
    id,
    post_id,
    viewer_id,
    viewed_at,
    view_date
FROM post_views
ORDER BY viewed_at DESC
LIMIT 5;

-- 4. TRACK_POST_VIEW FONKSİYONU VAR MI?
SELECT '4. FONKSİYON KONTROLÜ' as step;
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_name = 'track_post_view';

-- 5. GET_USER_CURRENT_MONTH_POST_VIEWS FONKSİYONU VAR MI?
SELECT '5. STATS FONKSİYONU KONTROLÜ' as step;
SELECT routine_name
FROM information_schema.routines
WHERE routine_name LIKE '%post%view%';

-- 6. MEVCUT KULLANICI
SELECT '6. CURRENT USER' as step;
SELECT auth.uid() as current_user_id;

-- 7. POSTLAR VE SAHİPLERİ
SELECT '7. İLK 5 POST VE SAHİPLERİ' as step;
SELECT 
    p.id as post_id,
    p.user_id as post_owner_id,
    p.content,
    p.created_at,
    pr.username as owner_username
FROM posts p
LEFT JOIN profiles pr ON pr.id = p.user_id
ORDER BY p.created_at DESC
LIMIT 5;

-- 8. MANUEL TEST - TRACK_POST_VIEW
SELECT '8. MANUEL TEST' as step;
DO $$
DECLARE
    test_post_id UUID;
    test_post_owner UUID;
    v_current_user UUID;
BEGIN
    -- İlk postu al
    SELECT id, user_id INTO test_post_id, test_post_owner
    FROM posts
    LIMIT 1;
    
    v_current_user := auth.uid();
    
    RAISE NOTICE 'Test Post ID: %', test_post_id;
    RAISE NOTICE 'Post Sahibi: %', test_post_owner;
    RAISE NOTICE 'Mevcut Kullanıcı: %', v_current_user;
    
    IF v_current_user IS NULL THEN
        RAISE NOTICE 'UYARI: Kullanıcı giriş yapmamış!';
    ELSIF v_current_user = test_post_owner THEN
        RAISE NOTICE 'UYARI: Kendi postunu görüntülemeye çalışıyorsun!';
    ELSE
        -- Fonksiyonu çağır
        PERFORM track_post_view(test_post_id);
        RAISE NOTICE 'track_post_view() başarıyla çalıştırıldı';
    END IF;
END $$;

-- 9. TEST SONRASI POST_VIEWS KONTROLÜ
SELECT '9. TEST SONRASI KONTROL' as step;
SELECT COUNT(*) as kayit_sayisi FROM post_views;

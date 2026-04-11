-- POST_VIEWS RLS POLİTİKALARI KONTROL

-- 1. POST_VIEWS TABLOSU VARMI?
SELECT '1. POST_VIEWS TABLOSU' as step;
SELECT 
    tablename,
    rowsecurity
FROM pg_tables 
WHERE tablename = 'post_views' 
AND schemaname = 'public';

-- 2. POST_VIEWS POLICIES
SELECT '2. POST_VIEWS POLICIES' as step;
SELECT 
    policyname,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'post_views';

-- 3. POST_VIEWS COLUMNS
SELECT '3. POST_VIEWS COLUMNS' as step;
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'post_views'
ORDER BY ordinal_position;

-- 4. TRACK_POST_VIEW FUNCTION
SELECT '4. TRACK_POST_VIEW FUNCTION' as step;
SELECT 
    routine_name,
    routine_type,
    data_type
FROM information_schema.routines
WHERE routine_name = 'track_post_view'
AND routine_schema = 'public';

-- 5. GET_USER_CURRENT_MONTH_POST_VIEWS FUNCTION
SELECT '5. GET_USER_CURRENT_MONTH_POST_VIEWS' as step;
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_name = 'get_user_current_month_post_views'
AND routine_schema = 'public';

-- 6. POST_VIEWS TABLOSUNDA TRIGGER VAR MI?
SELECT '6. POST_VIEWS TRIGGERS' as step;
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table
FROM information_schema.triggers
WHERE event_object_table = 'post_views';

-- 7. MANUAL INSERT TEST (RLS test)
SELECT '7. MANUAL INSERT TEST' as step;
INSERT INTO post_views (post_id, viewer_id, viewed_at, view_date)
VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,
    NOW(),
    CURRENT_DATE
)
ON CONFLICT DO NOTHING;

SELECT 'Test insert tamamlandı' as result;

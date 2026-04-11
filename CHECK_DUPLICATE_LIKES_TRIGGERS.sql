-- ==============================================================================
-- CHECK: Duplicate Likes Trigger Kontrolü
-- ==============================================================================
-- Beğeni sayısının çift artmasının nedeni duplicate trigger olabilir
-- ==============================================================================

-- 1. Tüm trigger'ları listele
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'post_likes'
ORDER BY trigger_name;

-- 2. Post likes count güncelleyen function'ları kontrol et
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name ILIKE '%like%count%';

-- 3. posts.likes_count'un nasıl güncellendiğini kontrol et
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd
FROM pg_policies 
WHERE tablename = 'post_likes'
ORDER BY policyname;

-- 4. Mevcut durum: posts.likes_count değerleri vs gerçek count
SELECT 
    p.id,
    p.likes_count as stored_count,
    (SELECT COUNT(*) FROM post_likes pl WHERE pl.post_id = p.id) as actual_count,
    (p.likes_count - (SELECT COUNT(*) FROM post_likes pl WHERE pl.post_id = p.id)) as difference
FROM posts p
WHERE p.likes_count != (SELECT COUNT(*) FROM post_likes pl WHERE pl.post_id = p.id)
LIMIT 20;

-- ============================================================================
-- BEĞENİ -1 HATASI KONTROL
-- ============================================================================
-- Kullanıcı şikayeti: "beğeniler -1 düşüyor beğeniler hatası düzelt"

-- 1. likes_count -1'den küçük olan postları kontrol et
SELECT 
    id,
    user_id,
    content,
    likes_count,
    comments_count,
    created_at
FROM public.posts
WHERE likes_count < 0
ORDER BY likes_count ASC
LIMIT 20;

-- 2. Tüm postların likes_count istatistikleri
SELECT 
    MIN(likes_count) as min_likes,
    MAX(likes_count) as max_likes,
    AVG(likes_count) as avg_likes,
    COUNT(*) as total_posts,
    COUNT(CASE WHEN likes_count < 0 THEN 1 END) as negative_count_posts
FROM public.posts;

-- 3. Her post için gerçek like sayısı ile likes_count'un uyuşup uyuşmadığını kontrol et
SELECT 
    p.id,
    p.likes_count as stored_count,
    COUNT(pl.id) as actual_count,
    p.likes_count - COUNT(pl.id) as difference
FROM public.posts p
LEFT JOIN public.post_likes pl ON pl.post_id = p.id
GROUP BY p.id, p.likes_count
HAVING p.likes_count != COUNT(pl.id)
ORDER BY difference DESC
LIMIT 20;

-- 4. Trigger'ların mevcut olup olmadığını kontrol et
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table IN ('post_likes', 'post_comments')
ORDER BY event_object_table, trigger_name;

-- 5. @mention trigger kontrolü
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'comment_mentions'
ORDER BY trigger_name;

-- 6. comment_mentions tablosu yapısı
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'comment_mentions'
ORDER BY ordinal_position;

-- 7. Son 10 mention kaydını kontrol et
SELECT 
    cm.id,
    cm.comment_id,
    cm.mentioned_user_id,
    cm.mentioned_by_user_id,
    cm.created_at,
    pc.content as comment_text
FROM public.comment_mentions cm
LEFT JOIN public.post_comments pc ON pc.id = cm.comment_id
ORDER BY cm.created_at DESC
LIMIT 10;

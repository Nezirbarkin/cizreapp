-- =====================================================
-- BEĞENİ VE YORUM SAYISI - HIZLI DEBUG
-- =====================================================

-- TRIGGER'LARI GÖR
SELECT 
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'post_likes'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- POSTS KOLONLARI
SELECT 
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'posts'
AND (column_name ILIKE '%count%' OR column_name ILIKE '%likes%' OR column_name ILIKE '%comments%')
ORDER BY column_name;

-- POSTS ÖRNEKLERİ
SELECT 
    id,
    likes_count,
    comments_count
FROM posts
LIMIT 10;

-- GERÇEK BEĞENİ SAYILARI
SELECT 
    post_id,
    COUNT(*) as real_likes
FROM post_likes
GROUP BY post_id
ORDER BY real_likes DESC
LIMIT 10;

-- KARŞILAŞTIRMA
SELECT 
    p.id,
    p.likes_count as db_likes,
    COALESCE(pl.real_likes, 0) as real_likes,
    p.comments_count as db_comments,
    COALESCE(pc.real_comments, 0) as real_comments
FROM posts p
LEFT JOIN (
    SELECT post_id, COUNT(*) as real_likes 
    FROM post_likes 
    GROUP BY post_id
) pl ON pl.post_id = p.id
LEFT JOIN (
    SELECT post_id, COUNT(*) as real_comments 
    FROM post_comments 
    GROUP BY post_id
) pc ON pc.post_id = p.id
ORDER BY p.created_at DESC
LIMIT 10;

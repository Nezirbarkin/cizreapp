-- =====================================================
-- BEĞENİ VE YORUM SAYISI SORUNLARI DEBUG
-- =====================================================
-- Sorunlar:
-- 1) Yorum sayısı gösterilmiyor
-- 2) Beğeniler rastgele artıyor ve 2'er 2'er artıyor
-- =====================================================

-- =====================================================
-- ADIM 1: POST_LIKES TRIGGER'LARINI GÖR
-- =====================================================

SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'post_likes'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- =====================================================
-- ADIM 2: POST_COMMENTS TRIGGER'LARINI GÖR
-- =====================================================

SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'post_comments'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- =====================================================
-- ADIM 3: POSTS TABLOSUNDA SAYAC ALANLARI
-- =====================================================

SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'posts'
AND (column_name ILIKE '%count%' OR column_name ILIKE '%likes%' OR column_name ILIKE '%comments%')
ORDER BY column_name;

-- =====================================================
-- ADIM 4: ÖRNEK POST VERİLERİ
-- =====================================================

-- Posts tablosundaki sayıları gör
SELECT
    id,
    likes_count,
    comments_count
FROM posts
LIMIT 10;

-- =====================================================
-- ADIM 5: BEĞENİ KAYIT SAYILARI
-- =====================================================

SELECT 
    post_id,
    COUNT(*) as like_count
FROM post_likes
GROUP BY post_id
ORDER BY like_count DESC
LIMIT 10;

-- =====================================================
-- ADIM 6: YORUM KAYIT SAYILARI
-- =====================================================

SELECT 
    post_id,
    COUNT(*) as comment_count
FROM post_comments
GROUP BY post_id
ORDER BY comment_count DESC
LIMIT 10;

-- =====================================================
-- ADIM 7: POSTS TABLOSUNU İLE KARŞILAŞTIRMA
-- =====================================================

-- Post tablosundaki sayı vs gerçek sayı
SELECT 
    p.id,
    p.likes_count as posts_likes,
    COALESCE(pl.actual_likes, 0) as actual_likes,
    p.comments_count as posts_comments,
    COALESCE(pc.actual_comments, 0) as actual_comments,
    CASE 
        WHEN p.likes_count <> COALESCE(pl.actual_likes, 0) THEN 'LIKES UYUŞMAZLIK'
        WHEN p.comments_count <> COALESCE(pc.actual_comments, 0) THEN 'COMMENTS UYUŞMAZLIK'
        ELSE 'OK'
    END as status
FROM posts p
LEFT JOIN (
    SELECT post_id, COUNT(*) as actual_likes 
    FROM post_likes 
    GROUP BY post_id
) pl ON pl.post_id = p.id
LEFT JOIN (
    SELECT post_id, COUNT(*) as actual_comments 
    FROM post_comments 
    GROUP BY post_id
) pc ON pc.post_id = p.id
ORDER BY p.created_at DESC
LIMIT 20;

-- =====================================================
-- ADIM 8: FONKSİYONLARI LİSTELE
-- =====================================================

-- Like count ile ilgili fonksiyonlar
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND (
    routine_name ILIKE '%like%count%' OR
    routine_name ILIKE '%increment%like%' OR
    routine_name ILIKE '%update%post%like%' OR
    routine_name ILIKE '%comment%count%' OR
    routine_name ILIKE '%increment%comment%'
)
ORDER BY routine_name;

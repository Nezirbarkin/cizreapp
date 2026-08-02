-- ============================================================
-- MEVCUT DURUM KONTROLÜ - Hiçbir değişiklik yapmaz, sadece raporlar
-- ============================================================

-- 1. Story likes trigger'ları var mı?
SELECT '1. STORY_LIKES TRIGGER DURUMU' AS bilgi;
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'story_likes';

-- 2. Stories tablosundaki likes_count kolonu var mı?
SELECT '2. STORIES TABLOSUNDA LIKES_COUNT KOLONU' AS bilgi;
SELECT column_name, data_type, column_default
FROM information_schema.columns 
WHERE table_name = 'stories' AND column_name = 'likes_count';

-- 3. Mevcut story'lerde likes_count vs gerçek beğeni sayıları karşılaştırması
SELECT '3. LIKES_COUNT VS GERÇEK BEĞENİ SAYILARI' AS bilgi;
SELECT 
    s.id,
    s.likes_count AS kayitli_count,
    COALESCE(sl.gercek_count, 0) AS gercek_count,
    CASE 
        WHEN s.likes_count = COALESCE(sl.gercek_count, 0) THEN '✅ EŞLEŞİYOR'
        ELSE '❌ UYUMSUZ'
    END AS durum
FROM stories s
LEFT JOIN (
    SELECT story_id, COUNT(*) AS gercek_count
    FROM story_likes
    GROUP BY story_id
) sl ON sl.story_id = s.id
WHERE s.expires_at > NOW()
ORDER BY s.created_at DESC
LIMIT 20;

-- 4. Toplam story_likes sayısı
SELECT '4. TOPLAM STORY_LIKES KAYITLARI' AS bilgi;
SELECT COUNT(*) AS toplam_begeni FROM story_likes;

-- 5. increment/decrement RPC fonksiyonları var mı?
SELECT '5. RPC FONKSİYONLARI' AS bilgi;
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_name IN ('increment_story_likes', 'decrement_story_likes', 'increment_story_likes_count', 'decrement_story_likes_count');
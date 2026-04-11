-- =====================================================
-- ÇOKLU TRIGGER SORUNU ÇÖZÜMÜ
-- =====================================================
-- Sorun: post_likes için birden fazla trigger var
-- Sonuç: Beğeniler 2-3-4 kat artıyor
-- =====================================================

-- ADIM 1: Mevcut Trigger'ları Gör
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'post_likes'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- ADIM 2: Yalnız Bir Trigger Bırak
-- =====================================================
-- Fazla trigger'ları sil (eğer 3 tane varsa)

-- İLK ÖNCE UYARI: Aşağıdaki trigger'lardan yalnız BİRİNİ bırakacağız
-- Diğerlerini sileceğiz

-- post_likes_count_trigger'ı SİL (varsa)
DROP TRIGGER IF EXISTS post_likes_count_trigger ON post_likes;

-- post_likes_insert_trigger'ı SİL (varsa)  
DROP TRIGGER IF EXISTS post_likes_insert_trigger ON post_likes;

-- notify_post_like_trigger'ı KAL (en önemli, bildirim için)
-- Diğer trigger'lar gerekli değil, increment_post_likes_count başlık sütunu güncelliyor

-- ADIM 3: post_comments TRIGGER'INI EKLE
-- =====================================================

-- post_comments trigger'ını oluştur
DROP TRIGGER IF EXISTS post_comments_count_trigger ON post_comments;

CREATE TRIGGER post_comments_count_trigger
    AFTER INSERT ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_post_comments_count();

-- UPDATE için de trigger ekle (yorum silinirse)
DROP TRIGGER IF EXISTS post_comments_delete_trigger ON post_comments;

CREATE TRIGGER post_comments_delete_trigger
    AFTER DELETE ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_post_comments_count();

-- ADIM 4: Sayıları Sıfırla ve Yeniden Hesapla
-- =====================================================

-- Beğeni sayılarını sıfırla
UPDATE posts SET likes_count = 0;

-- Gerçek beğeni sayılarından ayarla
UPDATE posts 
SET likes_count = (
    SELECT COUNT(*) FROM post_likes 
    WHERE post_likes.post_id = posts.id
);

-- Yorum sayılarını sıfırla
UPDATE posts SET comments_count = 0;

-- Gerçek yorum sayılarından ayarla
UPDATE posts 
SET comments_count = (
    SELECT COUNT(*) FROM post_comments 
    WHERE post_comments.post_id = posts.id
);

-- ADIM 5: KONTROL
-- =====================================================

-- post_likes trigger'ları (sadece notify_post_like_trigger kalmalı)
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'post_likes'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- post_comments trigger'ları (INSERT ve DELETE için 2 trigger)
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'post_comments'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- Düzeltilmiş sayılar
SELECT 
    id,
    likes_count,
    comments_count
FROM posts
WHERE likes_count > 0 OR comments_count > 0
LIMIT 10;

-- =====================================================
-- SONUÇ:
-- ✅ Beğeni sadece 1 kez sayılır
-- ✅ Yorum sayıları gösterilir
-- =====================================================

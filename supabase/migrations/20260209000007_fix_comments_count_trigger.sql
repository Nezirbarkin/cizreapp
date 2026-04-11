-- Yorum sayısını otomatik güncelleme trigger'ı
-- Yorum eklendiğinde/silindiğinde posts tablosundaki comments_count'u günceller

-- Önce var olan eski trigger'ları temizle
DROP TRIGGER IF EXISTS update_comments_count_on_insert ON post_comments;
DROP TRIGGER IF EXISTS update_comments_count_on_delete ON post_comments;
DROP FUNCTION IF EXISTS update_post_comments_count();

-- Yorum sayısını güncelleyen fonksiyon
CREATE OR REPLACE FUNCTION update_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Yorum eklendiğinde artır
        UPDATE posts
        SET comments_count = COALESCE(comments_count, 0) + 1
        WHERE id = NEW.post_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        -- Yorum silindiğinde azalt
        UPDATE posts
        SET comments_count = GREATEST(COALESCE(comments_count, 1) - 1, 0)
        WHERE id = OLD.post_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Yorum eklendiğinde trigger
CREATE TRIGGER update_comments_count_on_insert
    AFTER INSERT ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_post_comments_count();

-- Yorum silindiğinde trigger
CREATE TRIGGER update_comments_count_on_delete
    AFTER DELETE ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_post_comments_count();

-- Mevcut post'ların yorum sayılarını düzelt (comments_count null ise 0 yap, ardından doğru sayıları hesapla)
UPDATE posts
SET comments_count = 0
WHERE comments_count IS NULL;

-- Her post için gerçek yorum sayısını hesapla ve güncelle
UPDATE posts p
SET comments_count = (
    SELECT COUNT(*)
    FROM post_comments
    WHERE post_id = p.id
);

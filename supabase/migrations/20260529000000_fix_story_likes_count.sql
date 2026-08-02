-- ============================================================
-- STORY LIKES COUNT DÜZELTME - Bu SQL tüm sorunları çözer
-- Supabase SQL Editor'de çalıştırın
-- ============================================================

-- 1. Trigger fonksiyonları oluştur
CREATE OR REPLACE FUNCTION increment_story_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.stories
    SET likes_count = likes_count + 1
    WHERE id = NEW.story_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION decrement_story_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.stories
    SET likes_count = GREATEST(0, likes_count - 1)
    WHERE id = OLD.story_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Mevcut trigger'ları temizle (varsa)
DROP TRIGGER IF EXISTS trigger_increment_story_likes_count ON public.story_likes;
DROP TRIGGER IF EXISTS trigger_decrement_story_likes_count ON public.story_likes;

-- 3. Yeni trigger'ları oluştur
CREATE TRIGGER trigger_increment_story_likes_count
    AFTER INSERT ON public.story_likes
    FOR EACH ROW
    EXECUTE FUNCTION increment_story_likes_count();

CREATE TRIGGER trigger_decrement_story_likes_count
    AFTER DELETE ON public.story_likes
    FOR EACH ROW
    EXECUTE FUNCTION decrement_story_likes_count();

-- 4. Mevcut tüm hikayelerin likes_count'unu gerçek beğeni sayılarıyla düzelt
UPDATE public.stories s
SET likes_count = COALESCE(sl.gercek_count, 0)
FROM (
    SELECT story_id, COUNT(*) AS gercek_count
    FROM public.story_likes
    GROUP BY story_id
) sl
WHERE sl.story_id = s.id;

-- likes_count'u 0 olan ama story_likes kaydı olmayan hikayeleri de güncelle
UPDATE public.stories
SET likes_count = 0
WHERE likes_count IS NULL OR likes_count < 0;

-- 5. Eski RPC fonksiyonlarını no-op yap (trigger zaten işi yapıyor, çift saymayı önlemek için)
CREATE OR REPLACE FUNCTION increment_story_likes(story_id UUID)
RETURNS VOID AS $$
BEGIN
    NULL; -- Trigger AFTER INSERT ile zaten +1 yapıyor
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION decrement_story_likes(story_id UUID)
RETURNS VOID AS $$
BEGIN
    NULL; -- Trigger AFTER DELETE ile zaten -1 yapıyor
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. İzinleri güncelle
GRANT EXECUTE ON FUNCTION increment_story_likes(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION decrement_story_likes(UUID) TO authenticated;
-- ============================================================================
-- Story Likes Count Trigger
-- ============================================================================
-- Sorun: story_likes tablosuna insert/delete yapıldığında stories.likes_count
-- otomatik güncellenmiyordu. Sadece RPC fonksiyonları (increment_story_likes,
-- decrement_story_likes) ile güncelleniyordu. Bu RPC'ler bazen çağrılmıyor veya
-- hata veriyordu, bu yüzden likes_count her zaman 1-2 gibi yanlış değerler gösteriyordu.
--
-- Çözüm: Post'larda olduğu gibi, story_likes insert/delete'de stories.likes_count'u
-- otomatik güncelleyen trigger ekle. Ayrıca mevcut likes_count değerlerini düzelt.

-- 1. Function: Story like eklendiğinde count'u artır
CREATE OR REPLACE FUNCTION increment_story_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.stories
    SET likes_count = likes_count + 1
    WHERE id = NEW.story_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Function: Story like silindiğinde count'u azalt
CREATE OR REPLACE FUNCTION decrement_story_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.stories
    SET likes_count = GREATEST(0, likes_count - 1)
    WHERE id = OLD.story_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Mevcut trigger'ları temizle (varsa)
DROP TRIGGER IF EXISTS trigger_increment_story_likes_count ON public.story_likes;
DROP TRIGGER IF EXISTS trigger_decrement_story_likes_count ON public.story_likes;

-- 4. Trigger'ları oluştur
CREATE TRIGGER trigger_increment_story_likes_count
    AFTER INSERT ON public.story_likes
    FOR EACH ROW
    EXECUTE FUNCTION increment_story_likes_count();

CREATE TRIGGER trigger_decrement_story_likes_count
    AFTER DELETE ON public.story_likes
    FOR EACH ROW
    EXECUTE FUNCTION decrement_story_likes_count();

-- 5. Mevcut likes_count değerlerini düzelt (gerçek beğeni sayılarıyla eşleştir)
UPDATE public.stories s
SET likes_count = (
    SELECT COUNT(*)
    FROM public.story_likes sl
    WHERE sl.story_id = s.id
);

-- 6. RPC fonksiyonlarını no-op yap (trigger zaten işi yapıyor, çift saymayı önlemek için)
CREATE OR REPLACE FUNCTION increment_story_likes(story_id UUID)
RETURNS VOID AS $$
BEGIN
    -- Trigger AFTER INSERT ile zaten likes_count + 1 yapıyor
    -- RPC çağrıldığında çift saymayı önlemek için no-op
    NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION decrement_story_likes(story_id UUID)
RETURNS VOID AS $$
BEGIN
    -- Trigger AFTER DELETE ile zaten likes_count - 1 yapıyor
    -- RPC çağrıldığında çift saymayı önlemek için no-op
    NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. İzinleri koru
GRANT EXECUTE ON FUNCTION increment_story_likes(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION decrement_story_likes(UUID) TO authenticated;
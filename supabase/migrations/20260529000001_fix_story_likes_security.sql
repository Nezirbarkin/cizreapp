-- ============================================================
-- STORY LIKES GÜVENLİK DÜZELTMELERİ
-- ============================================================

-- 1. Trigger fonksiyonlarına search_path ekle (function_search_path_mutable uyarısı)
CREATE OR REPLACE FUNCTION increment_story_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.stories
    SET likes_count = likes_count + 1
    WHERE id = NEW.story_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION decrement_story_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.stories
    SET likes_count = GREATEST(0, likes_count - 1)
    WHERE id = OLD.story_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 2. RPC fonksiyonlarına search_path ekle
CREATE OR REPLACE FUNCTION increment_story_likes(story_id UUID)
RETURNS VOID AS $$
BEGIN
    NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION decrement_story_likes(story_id UUID)
RETURNS VOID AS $$
BEGIN
    NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. anon rolünden trigger fonksiyonlarının execute iznini kaldır
-- (sadece authenticated kullanıcılar beğeni yapabilir)
REVOKE EXECUTE ON FUNCTION increment_story_likes_count() FROM anon;
REVOKE EXECUTE ON FUNCTION decrement_story_likes_count() FROM anon;

-- 4. RPC fonksiyonlarından da anon iznini kaldır
REVOKE EXECUTE ON FUNCTION increment_story_likes(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION decrement_story_likes(UUID) FROM anon;
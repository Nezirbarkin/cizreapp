-- ============================================================================
-- POST LIKES COUNT TRIGGER FIX
-- ============================================================================
-- Sorun: post_likes tablosu var ama likes_count'u güncelleyen trigger yok.
-- Çözüm: post_likes insert/delete'de posts.likes_count'u güncelleyen trigger ekle.

-- 1. Posts tablosunda likes_count sütununun olduğundan emin ol
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS likes_count INTEGER DEFAULT 0;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS comments_count INTEGER DEFAULT 0;

-- 2. Function: Post like eklendiğinde count'u artır
CREATE OR REPLACE FUNCTION increment_post_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.posts
    SET likes_count = likes_count + 1
    WHERE id = NEW.post_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 3. Function: Post like silindiğinde count'u azalt
CREATE OR REPLACE FUNCTION decrement_post_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.posts
    SET likes_count = GREATEST(0, likes_count - 1)
    WHERE id = OLD.post_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 4. Drop eski trigger'lar varsa
DROP TRIGGER IF EXISTS post_likes_insert_trigger ON public.post_likes;
DROP TRIGGER IF EXISTS post_likes_delete_trigger ON public.post_likes;

-- 5. Trigger'ları oluştur
CREATE TRIGGER post_likes_insert_trigger
    AFTER INSERT ON public.post_likes
    FOR EACH ROW
    EXECUTE FUNCTION increment_post_likes_count();

CREATE TRIGGER post_likes_delete_trigger
    AFTER DELETE ON public.post_likes
    FOR EACH ROW
    EXECUTE FUNCTION decrement_post_likes_count();

-- 6. Mevcut likes_count'ları düzelt (eski kayıtlar için)
UPDATE public.posts p
SET likes_count = (
    SELECT COUNT(*)
    FROM public.post_likes pl
    WHERE pl.post_id = p.id
);

-- 7. Mevcut comments_count'ları düzelt (eski kayıtlar için)
UPDATE public.posts p
SET comments_count = (
    SELECT COUNT(*)
    FROM public.post_comments pc
    WHERE pc.post_id = p.id
);

DO $$
BEGIN
    RAISE NOTICE 'Post likes count trigger fix applied successfully!';
END $$;

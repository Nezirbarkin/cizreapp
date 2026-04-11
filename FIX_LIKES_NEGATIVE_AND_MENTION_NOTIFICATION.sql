-- ============================================================================
-- BEĞENİ -1 HATASI DÜZELTME VE @MENTION BİLDİRİM ONARIMI
-- ============================================================================
-- Sorun 1: Beğeni sayısı -1'e düşüyor
-- Sorun 2: @mention bildirimi gitmiyor
-- Çözüm: Tüm likes_count'ları düzelt, trigger'ları garanti et, mention trigger'ını onar

-- 1. Tüm negatif likes_count değerlerini 0 yap
UPDATE public.posts
SET likes_count = 0
WHERE likes_count < 0;

-- 2. Mevcut tüm postların likes_count'larını gerçek değerlerle güncelle
UPDATE public.posts p
SET likes_count = (
    SELECT COUNT(*)
    FROM public.post_likes pl
    WHERE pl.post_id = p.id
);

-- 3. Mevcut tüm postların comments_count'larını gerçek değerlerle güncelle
UPDATE public.posts p
SET comments_count = (
    SELECT COUNT(*)
    FROM public.post_comments pc
    WHERE pc.post_id = p.id
);

-- 4. Likes count trigger fonksiyonlarını yeniden oluştur (güvenli şekilde)
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

-- 5. Post likes trigger'ları oluştur
DROP TRIGGER IF EXISTS post_likes_insert_trigger ON public.post_likes;
CREATE TRIGGER post_likes_insert_trigger
    AFTER INSERT ON public.post_likes
    FOR EACH ROW
    EXECUTE FUNCTION increment_post_likes_count();

DROP TRIGGER IF EXISTS post_likes_delete_trigger ON public.post_likes;
CREATE TRIGGER post_likes_delete_trigger
    AFTER DELETE ON public.post_likes
    FOR EACH ROW
    EXECUTE FUNCTION decrement_post_likes_count();

-- 6. Comments count trigger fonksiyonlarını oluştur
CREATE OR REPLACE FUNCTION increment_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.posts
    SET comments_count = comments_count + 1
    WHERE id = NEW.post_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

CREATE OR REPLACE FUNCTION decrement_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.posts
    SET comments_count = GREATEST(0, comments_count - 1)
    WHERE id = OLD.post_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 7. Post comments trigger'ları oluştur
DROP TRIGGER IF EXISTS post_comments_insert_trigger ON public.post_comments;
CREATE TRIGGER post_comments_insert_trigger
    AFTER INSERT ON public.post_comments
    FOR EACH ROW
    EXECUTE FUNCTION increment_post_comments_count();

DROP TRIGGER IF EXISTS post_comments_delete_trigger ON public.post_comments;
CREATE TRIGGER post_comments_delete_trigger
    AFTER DELETE ON public.post_comments
    FOR EACH ROW
    EXECUTE FUNCTION decrement_post_comments_count();

-- 8. @Mention trigger'ını garanti et (notification için)
CREATE OR REPLACE FUNCTION notify_comment_mention()
RETURNS TRIGGER AS $$
DECLARE
    commenter_info JSONB;
    comment_content TEXT;
BEGIN
    -- Kendini mention ederse notification gönderme
    IF NEW.mentioned_user_id = NEW.mentioned_by_user_id THEN
        RETURN NEW;
    END IF;

    -- Yorum içeriğini al
    SELECT content INTO comment_content
    FROM public.post_comments
    WHERE id = NEW.comment_id;

    -- Yorum yapanın bilgisini al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO commenter_info
    FROM public.profiles p
    WHERE p.id = NEW.mentioned_by_user_id;

    -- Notification ekle (duplicate önlemek için yoksa ekle)
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content,
        actor_id,
        actor_name,
        actor_avatar,
        entity_id,
        is_read,
        created_at
    ) VALUES (
        NEW.mentioned_user_id,
        'comment_mention',
        (commenter_info->>'full_name') || ' seni bir yorumda bahsetti',
        COALESCE(SUBSTRING(comment_content FROM 1 FOR 100), 'Mention'),
        NEW.mentioned_by_user_id,
        commenter_info->>'full_name',
        commenter_info->>'avatar_url',
        NEW.comment_id,
        false,
        NOW()
    ) ON CONFLICT DO NOTHING; -- Duplicate notification'ı önle

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 9. Mention trigger'ını oluştur/güncelle
DROP TRIGGER IF EXISTS notify_comment_mention_trigger ON public.comment_mentions;
CREATE TRIGGER notify_comment_mention_trigger
    AFTER INSERT ON public.comment_mentions
    FOR EACH ROW
    EXECUTE FUNCTION notify_comment_mention();

-- 10. Kontrol sorguları
DO $$
DECLARE
    neg_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO neg_count FROM public.posts WHERE likes_count < 0;
    
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'BEĞENİ -1 HATASI DÜZELTME TAMAMLANDI!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Negatif likes_count: % (0 olmalı)', neg_count;
    RAISE NOTICE 'Triggerlar: post_likes, post_comments, comment_mentions için hazır';
    RAISE NOTICE '================================================================';
END $$;

-- Sonuçları görüntüle
SELECT 
    'Negatif likes_count' as check_type,
    COUNT(*) as count
FROM public.posts
WHERE likes_count < 0

UNION ALL

SELECT 
    'Mention trigger aktif',
    COUNT(*)
FROM information_schema.triggers
WHERE trigger_name = 'notify_comment_mention_trigger';

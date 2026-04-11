-- ============================================================================
-- STORY LIKE NOTIFICATION TRIGGER
-- Hikaye beğenildiğinde hikaye sahibine bildirim gönder
-- ============================================================================

-- Story beğenildiğinde notification oluştur
CREATE OR REPLACE FUNCTION notify_story_like()
RETURNS TRIGGER AS $$
DECLARE
    story_owner_id UUID;
    liker_info JSONB;
BEGIN
    -- Hikaye sahibini bul
    SELECT user_id INTO story_owner_id
    FROM public.stories
    WHERE id = NEW.story_id;

    -- Kendi hikayesini beğenirse notification gönderme
    IF story_owner_id IS NULL OR story_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    -- Beğeneni bilgisini al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO liker_info
    FROM public.profiles p
    WHERE p.id = NEW.user_id;

    -- Notification ekle
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
        story_owner_id,
        'story_like',
        (liker_info->>'full_name') || ' hikayeni beğendi',
        'Hikaye Beğenisi',
        NEW.user_id,
        liker_info->>'full_name',
        liker_info->>'avatar_url',
        NEW.story_id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger'ı oluştur
DROP TRIGGER IF EXISTS notify_story_like_trigger ON public.story_likes;
CREATE TRIGGER notify_story_like_trigger
    AFTER INSERT ON public.story_likes
    FOR EACH ROW
    EXECUTE FUNCTION notify_story_like();

SELECT '✅ Story like notification trigger oluşturuldu' AS result;

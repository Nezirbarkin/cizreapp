-- ============================================================================
-- HİKAYE TEPKİLERİ (EMOJİ) + TEPKİ DEĞİŞTİRME
-- ============================================================================
-- Önceki durumda hikayeye yalnızca "kalp" atılabiliyordu (story_likes'ta emoji
-- alanı yoktu) ve tablonun UPDATE politikası olmadığı için StoryService'in
-- upsert(onConflict: story_id,user_id) çağrısı, kayıt zaten varsa RLS'e
-- takılıp hata veriyordu.
--
-- Bu migration:
--   * story_likes.emoji sütununu ekler (varsayılan ❤️),
--   * kullanıcının kendi tepkisini güncelleyebilmesi için UPDATE politikası
--     ekler,
--   * bildirim trigger'ını emoji'yi gösterecek ve tekrar bildirim
--     yığmayacak şekilde günceller (aynı actor + aynı hikaye için tek kayıt).

begin;

-- 1) Emoji sütunu
ALTER TABLE public.story_likes
  ADD COLUMN IF NOT EXISTS emoji text NOT NULL DEFAULT '❤️';

UPDATE public.story_likes SET emoji = '❤️' WHERE emoji IS NULL OR emoji = '';

COMMENT ON COLUMN public.story_likes.emoji IS
  'Hikayeye verilen tepki emojisi. Klasik beğeni = ❤️';

-- 2) Kullanıcı kendi tepkisini değiştirebilsin (upsert UPDATE yolu)
DROP POLICY IF EXISTS "Users can update their own story likes" ON public.story_likes;
CREATE POLICY "Users can update their own story likes"
ON public.story_likes
FOR UPDATE
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

-- 3) Bildirim: emoji'yi göster, aynı hikaye için tekrar yığma
CREATE OR REPLACE FUNCTION public.notify_story_like()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    story_owner_id UUID;
    liker_info JSONB;
    v_emoji TEXT := COALESCE(NEW.emoji, '❤️');
BEGIN
    SELECT user_id INTO story_owner_id
    FROM public.stories
    WHERE id = NEW.story_id;

    -- Kendi hikayesine tepki verirse bildirim gönderme
    IF story_owner_id IS NULL OR story_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    -- Aynı kişinin aynı hikayeye önceki tepki bildirimini temizle
    -- (tepki değiştirildiğinde iki bildirim kalmasın)
    DELETE FROM public.notifications
    WHERE user_id = story_owner_id
      AND actor_id = NEW.user_id
      AND type = 'story_like'
      AND entity_id = NEW.story_id::text;

    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO liker_info
    FROM public.profiles p
    WHERE p.id = NEW.user_id;

    INSERT INTO public.notifications (
        user_id, type, title, content,
        actor_id, actor_name, actor_avatar, entity_id, is_read, created_at
    ) VALUES (
        story_owner_id,
        'story_like',
        COALESCE(liker_info->>'full_name', 'Bir kullanıcı') || ' hikayene ' || v_emoji || ' gönderdi',
        'Hikaye tepkisi',
        NEW.user_id,
        liker_info->>'full_name',
        liker_info->>'avatar_url',
        NEW.story_id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS notify_story_like_trigger ON public.story_likes;
CREATE TRIGGER notify_story_like_trigger
AFTER INSERT OR UPDATE OF emoji ON public.story_likes
FOR EACH ROW
EXECUTE FUNCTION public.notify_story_like();

-- 4) likes_count trigger'ı UPDATE'te tetiklenmemeli (emoji değişimi beğeni
--    sayısını artırmamalı). Mevcut trigger zaten yalnızca INSERT/DELETE'te
--    tanımlı; güvence için yeniden oluşturuluyor.
DROP TRIGGER IF EXISTS trigger_increment_story_likes_count ON public.story_likes;
CREATE TRIGGER trigger_increment_story_likes_count
AFTER INSERT ON public.story_likes
FOR EACH ROW
EXECUTE FUNCTION public.increment_story_likes_count();

commit;

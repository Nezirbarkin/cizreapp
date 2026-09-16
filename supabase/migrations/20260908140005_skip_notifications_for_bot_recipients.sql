-- =============================================================================
-- 20260908140005_skip_notifications_for_bot_recipients.sql
-- -----------------------------------------------------------------------------
-- SORUN: Botlar birbirini takip edip birbirinin gönderilerini beğendikçe
-- `notify_new_follower` ve `notify_post_like` trigger'ları BOT hesaplarına
-- bildirim yazıyor. Bu bildirimleri kimse okumaz (botun oturumu yoktur) ama
-- `notifications` tablosunda sürekli birikir.
--
-- ÇÖZÜM: Her iki trigger fonksiyonuna, ALICI bot ise erken çıkış ekle.
-- Gerçek kullanıcılara giden bildirimler aynen korunur — bot bir GERÇEK
-- kullanıcıyı takip ettiğinde veya gönderisini beğendiğinde bildirim yine
-- oluşur (zaten istenen davranış budur).
--
-- Fonksiyon gövdeleri, canlıdaki güncel tanımlarının birebir kopyasıdır;
-- yalnız başlarına bot kontrolü eklenmiştir.
-- =============================================================================

begin;

CREATE OR REPLACE FUNCTION public.notify_new_follower()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_existing_notification_id uuid;
    follower_info JSONB;
BEGIN
    -- Kendini takip edemez (guard clause)
    IF NEW.follower_id = NEW.following_id THEN
        RETURN NEW;
    END IF;

    -- Alıcı bir bot ise bildirim üretme (okunmayacak, sadece tablo şişirir).
    IF EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = NEW.following_id AND p.is_bot = true
    ) THEN
        RETURN NEW;
    END IF;

    -- DUPLICATE KONTROLÜ: Son 24 saatte aynı notification var mı?
    SELECT id INTO v_existing_notification_id
    FROM public.notifications
    WHERE user_id = NEW.following_id
      AND actor_id = NEW.follower_id
      AND type IN ('new_follower', 'follow')
      AND created_at > NOW() - INTERVAL '24 hours'
    LIMIT 1;

    IF v_existing_notification_id IS NOT NULL THEN
        RAISE NOTICE 'Duplicate follow notification prevented for user %', NEW.following_id;
        RETURN NEW;
    END IF;

    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO follower_info
    FROM public.profiles p
    WHERE p.id = NEW.follower_id;

    INSERT INTO public.notifications (
        user_id, type, title, content, actor_id, actor_name, actor_avatar,
        is_read, created_at
    ) VALUES (
        NEW.following_id,
        'new_follower',
        (follower_info->>'full_name') || ' seni takip etti',
        'Yeni takipçi',
        NEW.follower_id,
        follower_info->>'full_name',
        follower_info->>'avatar_url',
        false,
        NOW()
    );

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_post_like()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    post_owner_id UUID;
    liker_info JSONB;
BEGIN
    SELECT user_id INTO post_owner_id
    FROM public.posts WHERE id = NEW.post_id;

    IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    -- Gönderi sahibi bir bot ise bildirim üretme.
    IF EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = post_owner_id AND p.is_bot = true
    ) THEN
        RETURN NEW;
    END IF;

    SELECT jsonb_build_object(
        'id', p.id, 'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO liker_info
    FROM public.profiles p WHERE p.id = NEW.user_id;

    INSERT INTO public.notifications (
        user_id, type, title, content, actor_id, actor_name, actor_avatar,
        entity_id, is_read, created_at
    ) VALUES (
        post_owner_id, 'post_like',
        (liker_info->>'full_name') || ' senin gönderini beğendi',
        'Beğeni', NEW.user_id,
        liker_info->>'full_name', liker_info->>'avatar_url',
        NEW.post_id, false, NOW()
    );

    RETURN NEW;
END;
$function$;

-- Birikmiş bot bildirimlerini temizle.
DELETE FROM public.notifications n
USING public.profiles p
WHERE p.id = n.user_id AND p.is_bot = true;

commit;

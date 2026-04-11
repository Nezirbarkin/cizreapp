-- =====================================================
-- DUPLICATE NOTIFICATION SORUNU ÇÖZÜMÜ
-- =====================================================
-- Sorun: Takip isteğinde 3 adet aynı bildirim çıkıyor
-- Çözüm: Notification oluştururken duplicate kontrolü ekle
-- =====================================================

-- 1. notify_new_follower fonksiyonunu güncelle - duplicate kontrolü ile
CREATE OR REPLACE FUNCTION notify_new_follower()
RETURNS TRIGGER AS $$
DECLARE
    v_existing_notification_id uuid;
    follower_info JSONB;
BEGIN
    -- Kendini takip edemez (guard clause)
    IF NEW.follower_id = NEW.following_id THEN
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

    -- Eğer zaten bildirim varsa, yeni oluşturma
    IF v_existing_notification_id IS NOT NULL THEN
        RAISE NOTICE 'Duplicate follow notification prevented for user %', NEW.following_id;
        RETURN NEW;
    END IF;

    -- Takip edenin bilgisini al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO follower_info
    FROM public.profiles p
    WHERE p.id = NEW.follower_id;

    -- Notification ekle
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content,
        actor_id,
        actor_name,
        actor_avatar,
        is_read,
        created_at
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
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 2. Follow request notification fonksiyonu - duplicate kontrolü ile
CREATE OR REPLACE FUNCTION notify_follow_request()
RETURNS TRIGGER AS $$
DECLARE
    v_existing_notification_id uuid;
    requester_info JSONB;
BEGIN
    -- Kendi kendine istek gönderemez
    IF NEW.follower_id = NEW.following_id THEN
        RETURN NEW;
    END IF;

    -- Sadece pending status için notification gönder
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;

    -- DUPLICATE KONTROLÜ: Son 24 saatte aynı notification var mı?
    SELECT id INTO v_existing_notification_id
    FROM public.notifications
    WHERE user_id = NEW.following_id
      AND actor_id = NEW.follower_id
      AND type = 'follow_request'
      AND created_at > NOW() - INTERVAL '24 hours'
    LIMIT 1;

    -- Eğer zaten bildirim varsa, yeni oluşturma
    IF v_existing_notification_id IS NOT NULL THEN
        RAISE NOTICE 'Duplicate follow request notification prevented for user %', NEW.following_id;
        RETURN NEW;
    END IF;

    -- İstek gönderenin bilgisini al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO requester_info
    FROM public.profiles p
    WHERE p.id = NEW.follower_id;

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
        NEW.following_id,
        'follow_request',
        (requester_info->>'full_name') || ' seni takip etmek istiyor',
        'Takip isteği',
        NEW.follower_id,
        requester_info->>'full_name',
        requester_info->>'avatar_url',
        NEW.id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 3. Follow request accepted notification fonksiyonu - duplicate kontrolü ile
CREATE OR REPLACE FUNCTION notify_follow_request_accepted()
RETURNS TRIGGER AS $$
DECLARE
    v_existing_notification_id uuid;
    follower_info JSONB;
BEGIN
    -- Sadece accepted status'a geçişte notification gönder
    IF OLD.status = 'accepted' OR NEW.status != 'accepted' THEN
        RETURN NEW;
    END IF;

    -- DUPLICATE KONTROLÜ: Son 24 saatte aynı notification var mı?
    SELECT id INTO v_existing_notification_id
    FROM public.notifications
    WHERE user_id = NEW.follower_id
      AND actor_id = NEW.following_id
      AND type = 'follow_request_accepted'
      AND created_at > NOW() - INTERVAL '24 hours'
    LIMIT 1;

    -- Eğer zaten bildirim varsa, yeni oluşturma
    IF v_existing_notification_id IS NOT NULL THEN
        RAISE NOTICE 'Duplicate follow request accepted notification prevented for user %', NEW.follower_id;
        RETURN NEW;
    END IF;

    -- Takip edilenin bilgisini al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO follower_info
    FROM public.profiles p
    WHERE p.id = NEW.following_id;

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
        NEW.follower_id,
        'follow_request_accepted',
        (follower_info->>'full_name') || ' senin takip isteğini kabul etti',
        'Takip isteği kabul edildi',
        NEW.following_id,
        follower_info->>'full_name',
        follower_info->>'avatar_url',
        NEW.id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- =====================================================
-- TRIGGER'LARI OLUŞTUR / GÜNCELLE
-- =====================================================

-- Follows trigger (notify_new_follower için)
DROP TRIGGER IF EXISTS notify_new_follower_trigger ON public.follows;
CREATE TRIGGER notify_new_follower_trigger
    AFTER INSERT ON public.follows
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_follower();

-- Follow requests trigger (notify_follow_request için)
DROP TRIGGER IF EXISTS notify_follow_request_trigger ON public.follow_requests;
CREATE TRIGGER notify_follow_request_trigger
    AFTER INSERT ON public.follow_requests
    FOR EACH ROW
    EXECUTE FUNCTION notify_follow_request();

-- Follow requests status update trigger (notify_follow_request_accepted için)
DROP TRIGGER IF EXISTS notify_follow_request_accepted_trigger ON public.follow_requests;
CREATE TRIGGER notify_follow_request_accepted_trigger
    AFTER UPDATE ON public.follow_requests
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION notify_follow_request_accepted();

-- =====================================================
-- MEVCUT DUPLICATE NOTIFICATIONS'I TEMİZLE (Opsiyonel)
-- =====================================================

-- Eski duplicate notification'ları temizlemek için:
-- Aynı user_id, actor_id ve type'a sahip ve 24 saat içindeki
-- duplicate'lerden sadece birini tut

-- WITH ranked_notifications AS (
--     SELECT 
--         id,
--         ROW_NUMBER() OVER (
--             PARTITION BY user_id, actor_id, type,
--                          DATE_TRUNC('day', created_at)
--             ORDER BY created_at DESC
--         ) as rn
--     FROM public.notifications
--     WHERE type IN ('new_follower', 'follow_request', 'follow')
--       AND created_at > NOW() - INTERVAL '30 days'
-- )
-- DELETE FROM public.notifications
-- WHERE id IN (
--     SELECT id FROM ranked_notifications WHERE rn > 1
-- );

-- =====================================================
-- KONTROL
-- =====================================================

-- Trigger kontrolü
SELECT 
    trigger_name,
    event_object_table,
    event_manipulation
FROM information_schema.triggers
WHERE trigger_name LIKE '%follow%'
ORDER BY event_object_table, trigger_name;

-- Fonksiyon kontrolü
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name LIKE '%follow%'
ORDER BY routine_name;

-- =====================================================
-- SONUÇ
-- =====================================================
-- ✅ notify_new_follower - duplicate kontrolü ile güncellendi
-- ✅ notify_follow_request - yeni oluşturuldu (duplicate kontrolü ile)
-- ✅ notify_follow_request_accepted - yeni oluşturuldu (duplicate kontrolü ile)
-- ✅ Trigger'lar güncellendi
-- 
-- Her fonksiyon son 24 saatte aynı notification var mı kontrol eder
-- Varsa yeni notification oluşturmaz
-- =====================================================

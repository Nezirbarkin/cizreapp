-- =====================================================
-- MESAJ PUSH NOTIFICATION TRIGGER'I
-- =====================================================
-- Mesaj geldiğinde alıcıya push notification gönderir
-- =====================================================

-- 1. Mesaj notification fonksiyonu (push ile birlikte)
CREATE OR REPLACE FUNCTION notify_new_message()
RETURNS TRIGGER AS $$
DECLARE
    v_recipient_id uuid;
    v_conversation_other_user_id uuid;
    sender_info JSONB;
    v_notification_title text;
    v_notification_body text;
    v_result jsonb;
BEGIN
    -- Konuşmadaki diğer kullanıcıyı bul (alıcı)
    -- conversations tablosunda user_id = current_user, other_user_id = sender
    -- OR user_id = sender, other_user_id = current_user
    
    -- Alıcıyı bul: conversations tablosunda user_id != NEW.sender_id olan kayıt
    SELECT user_id INTO v_recipient_id
    FROM public.conversations
    WHERE id = NEW.conversation_id
      AND user_id != NEW.sender_id
    LIMIT 1;
    
    -- Eğer alıcı bulunamazsa, other_user_id'i kontrol et
    IF v_recipient_id IS NULL THEN
        SELECT other_user_id INTO v_recipient_id
        FROM public.conversations
        WHERE id = NEW.conversation_id
          AND other_user_id != NEW.sender_id
        LIMIT 1;
    END IF;
    
    -- Alıcı bulunamazsa (kendi kendine mesaj gibi), notification gönderme
    IF v_recipient_id IS NULL OR v_recipient_id = NEW.sender_id THEN
        RETURN NEW;
    END IF;
    
    -- Gönderenin bilgisini al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO sender_info
    FROM public.profiles p
    WHERE p.id = NEW.sender_id;
    
    -- Notification metni
    v_notification_title := (sender_info->>'full_name') || ' sana bir mesaj gönderdi';
    
    -- Mesaj içeriği (çok uzunsa kısalt)
    v_notification_body := CASE
        WHEN LENGTH(NEW.content) > 100 THEN SUBSTRING(NEW.content FROM 1 FOR 100) || '...'
        ELSE NEW.content
    END;
    
    -- Notification tablosuna kayıt ekle
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
        v_recipient_id,
        'message',
        v_notification_title,
        v_notification_body,
        NEW.sender_id,
        sender_info->>'full_name',
        sender_info->>'avatar_url',
        NEW.conversation_id::text,
        false,
        NOW()
    );
    
    -- Push notification notification trigger tarafından otomatik gönderilecek
    -- (notifications tablosuna INSERT yapınca tetikleniyor)
    
    RAISE NOTICE 'Message notification created for user %', v_recipient_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- =====================================================
-- TRIGGER'I OLUŞTUR
-- =====================================================

DROP TRIGGER IF EXISTS notify_new_message_trigger ON public.messages;
CREATE TRIGGER notify_new_message_trigger
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_message();

-- =====================================================
-- KONTROL
-- =====================================================

-- Fonksiyon kontrolü
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'notify_new_message';

-- Trigger kontrolü
SELECT 
    trigger_name,
    event_object_table,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'notify_new_message_trigger';

-- =====================================================
-- SEND_PUSH_ON_NOTIFICATION'U MESSAGE İÇİN GÜNCELLE
-- =====================================================

-- send_push_on_notification fonksiyonunda 'message' tipi için kontrol eklendi mi kontrol et
-- Eğer eksikse aşağıdaki kod çalıştırın:

-- CREATE OR REPLACE FUNCTION send_push_on_notification()
-- RETURNS TRIGGER
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- SET search_path = public
-- AS $$
-- DECLARE
--     v_prefs record;
--     v_should_send boolean := false;
--     v_result jsonb;
-- BEGIN
--     -- Bildirim tercihlerini al
--     SELECT * INTO v_prefs
--     FROM notification_preferences
--     WHERE user_id = NEW.user_id;
--
--     -- Tercih yoksa varsayılan olarak gönder (true)
--     IF v_prefs IS NULL THEN
--         v_should_send := true;
--     ELSE
--         -- Global kontrol önce
--         IF v_prefs.push_enabled = false THEN
--             v_should_send := false;
--         ELSE
--             -- Tip bazlı kontrol
--             CASE NEW.type
--                 WHEN 'post_like' THEN v_should_send := COALESCE(v_prefs.likes_enabled, true);
--                 WHEN 'like' THEN v_should_send := COALESCE(v_prefs.likes_enabled, true);
--                 WHEN 'post_comment' THEN v_should_send := COALESCE(v_prefs.comments_enabled, true);
--                 WHEN 'comment' THEN v_should_send := COALESCE(v_prefs.comments_enabled, true);
--                 WHEN 'new_follower' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
--                 WHEN 'follow' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
--                 WHEN 'follow_request' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
--                 WHEN 'follow_request_accepted' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
--                 WHEN 'comment_mention' THEN v_should_send := COALESCE(v_prefs.mentions, true);
--                 WHEN 'mention' THEN v_should_send := COALESCE(v_prefs.mentions, true);
--                 WHEN 'message' THEN v_should_send := true; -- ✅ Mesajlar için her zaman gönder
--                 WHEN 'new_order' THEN v_should_send := COALESCE(v_prefs.order_updates_enabled, true);
--                 WHEN 'order_status' THEN v_should_send := COALESCE(v_prefs.order_updates_enabled, true);
--                 WHEN 'order' THEN v_should_send := COALESCE(v_prefs.order_updates_enabled, true);
--                 ELSE v_should_send := true;
--             END CASE;
--         END IF;
--     END IF;
--
--     -- Push gönderilmeliyse
--     IF v_should_send THEN
--         RAISE NOTICE 'Sending push for notification % (type: %)', NEW.id, NEW.type;
--
--         SELECT send_fcm_push_notification(
--             NEW.user_id,
--             NEW.title,
--             NEW.content,
--             jsonb_build_object(
--                 'type', NEW.type,
--                 'notification_id', NEW.id::text,
--                 'actor_id', COALESCE(NEW.actor_id::text, ''),
--                 'actor_name', COALESCE(NEW.actor_name, ''),
--                 'actor_avatar', COALESCE(NEW.actor_avatar, ''),
--                 'entity_id', COALESCE(NEW.entity_id, '')
--             )
--         ) INTO v_result;
--
--         RAISE NOTICE 'Push result: %', v_result::text;
--     ELSE
--         RAISE NOTICE 'Push disabled for notification % (type: %)', NEW.id, NEW.type;
--     END IF;
--
--     RETURN NEW;
-- END;
-- $$;

-- =====================================================
-- SONUÇ
-- =====================================================
-- ✅ notify_new_message fonksiyonu oluşturuldu
-- ✅ notify_new_message_trigger oluşturuldu
-- ✅ Mesaj geldiğinde notifications tablosuna kayıt eklenir
-- ✅ send_push_on_notification trigger'ı tetiklenir ve push gönderilir
--
-- NOT: send_push_on_notification fonksiyonunda 'message' tipi için
-- v_should_send := true satırı olduğundan emin olun
-- =====================================================

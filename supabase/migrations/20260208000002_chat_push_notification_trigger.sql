-- ============================================================================
-- CHAT PUSH NOTIFICATION TRIGGER
-- ============================================================================
-- Yeni mesaj geldiğinde alıcıya push notification gönderir
-- 
-- Bu trigger messages tablosuna INSERT yapıldığında tetiklenir ve
-- Edge Function çağırarak push notification gönderir.

-- 1. Yeni mesaj geldiğinde push notification gönderen fonksiyon
CREATE OR REPLACE FUNCTION notify_new_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_conversation RECORD;
    v_sender_name TEXT;
    v_receiver_id UUID;
    v_receiver_fcm_token TEXT;
    v_notification_payload JSONB;
BEGIN
    -- Konuşma bilgilerini al
    SELECT * INTO v_conversation
    FROM conversations
    WHERE id = NEW.conversation_id;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- Alıcı ID'sini belirle (gönderici user_id ise alıcı other_user_id, tersi de geçerli)
    IF v_conversation.user_id = NEW.sender_id THEN
        v_receiver_id := v_conversation.other_user_id;
    ELSE
        v_receiver_id := v_conversation.user_id;
    END IF;

    -- Gönderici ismini al
    SELECT COALESCE(full_name, username, 'Birisi') INTO v_sender_name
    FROM profiles
    WHERE id = NEW.sender_id;

    -- Alıcının FCM token'ını al
    SELECT fcm_token INTO v_receiver_fcm_token
    FROM profiles
    WHERE id = v_receiver_id
    AND fcm_token IS NOT NULL
    AND fcm_token != '';

    -- Eğer FCM token yoksa, işlemi bitir
    IF v_receiver_fcm_token IS NULL OR v_receiver_fcm_token = '' THEN
        RETURN NEW;
    END IF;

    -- Notification payload oluştur
    v_notification_payload := jsonb_build_object(
        'fcm_token', v_receiver_fcm_token,
        'title', v_sender_name || ' size mesaj gönderdi',
        'body', CASE 
            WHEN length(NEW.content) > 100 THEN substring(NEW.content, 1, 100) || '...'
            ELSE NEW.content
        END,
        'data', jsonb_build_object(
            'type', 'new_message',
            'conversation_id', NEW.conversation_id,
            'sender_id', NEW.sender_id,
            'message_id', NEW.id
        )
    );

    -- Notification tablosuna kaydet (body yerine message kullan - mevcut tabloya uygun)
    INSERT INTO notifications (
        user_id,
        type,
        title,
        message,
        data,
        is_read
    ) VALUES (
        v_receiver_id,
        'message',
        v_sender_name || ' size mesaj gönderdi',
        CASE
            WHEN length(NEW.content) > 100 THEN substring(NEW.content, 1, 100) || '...'
            ELSE NEW.content
        END,
        jsonb_build_object(
            'conversation_id', NEW.conversation_id,
            'sender_id', NEW.sender_id,
            'message_id', NEW.id
        ),
        FALSE
    );

    -- Edge function çağır (async - hatayı yoksay)
    BEGIN
        PERFORM net.http_post(
            url := current_setting('app.settings.edge_function_url', true) || '/send-push-notification',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
            ),
            body := v_notification_payload
        );
    EXCEPTION WHEN OTHERS THEN
        -- HTTP çağrısı başarısız olsa bile devam et
        NULL;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Mevcut trigger'ı sil ve yeniden oluştur
DROP TRIGGER IF EXISTS on_new_message_notify ON messages;

CREATE TRIGGER on_new_message_notify
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_message();

-- 3. notification_types enum'una 'message' tipini ekle (eğer yoksa)
DO $$
BEGIN
    -- notification_type enum'u varsa ve 'message' değeri yoksa ekle
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_type') THEN
        BEGIN
            ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'message';
        EXCEPTION WHEN OTHERS THEN
            -- Zaten varsa veya enum yoksa devam et
            NULL;
        END;
    END IF;
END $$;

-- 4. Notifications tablosunda type sütunu kontrolü
-- (Eğer type sütunu notification_type enum kullanıyorsa, 'message' zaten eklenmiş olmalı)
-- (Eğer text ise herhangi bir değer alabilir)

COMMENT ON FUNCTION notify_new_message() IS 'Yeni mesaj geldiğinde alıcıya push notification gönderir ve notifications tablosuna kaydeder';

-- ============================================================================
-- CHAT NOTIFICATION TRIGGER DÜZELTMESİ
-- ============================================================================
-- Sorun: notify_new_message fonksiyonunda notifications tablosuna insert yaparken
-- 'body' sütunu kullanılıyor ama tabloda 'message' sütunu var.
-- Çözüm: Mevcut trigger ve fonksiyonu drop edip doğru sütun adıyla yeniden oluştur.

-- Önce mevcut trigger'ı drop et
DROP TRIGGER IF EXISTS on_new_message_notify ON messages;

-- Mevcut fonksiyonu drop et
DROP FUNCTION IF EXISTS notify_new_message();

-- Yeni fonksiyonu doğru sütun adıyla oluştur
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

    -- Alıcı ID'sini belirle
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

    -- Notification tablosuna kaydet (CONTENT sütunu ile - mevcut notifications yapısına uygun)
    INSERT INTO notifications (
        user_id,
        type,
        title,
        content,  -- 'body' veya 'message' yerine 'content'
        actor_id,
        entity_id,
        is_read
    ) VALUES (
        v_receiver_id,
        'comment',  -- 'message' type notifications'da yok, 'comment' kullan
        v_sender_name || ' size mesaj gönderdi',
        CASE
            WHEN length(NEW.content) > 100 THEN substring(NEW.content, 1, 100) || '...'
            ELSE NEW.content
        END,
        NEW.sender_id,
        NEW.conversation_id::TEXT,
        FALSE
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı yeniden oluştur
CREATE TRIGGER on_new_message_notify
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_message();

COMMENT ON FUNCTION notify_new_message() IS 'Yeni mesaj geldiğinde alıcıya notification kaydeder (body yerine message sütunu kullanır)';

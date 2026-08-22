-- ============================================================================
-- PUSH NOTIFICATION EKLE: Mesaj geldiginde push gondermek icin
-- ============================================================================

-- 1. Mevcut check constraint tamamen kaldir (eski ve yeni tiplere izin ver)
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- 2. Yeni check constraint EKLEME - type serbest olsun (TEXT zaten)
-- Artik herhangi bir type kabul edilir

-- 3. Push notification gondermek icin trigger ekle
CREATE OR REPLACE FUNCTION notify_new_message_push()
RETURNS TRIGGER AS $$
DECLARE
    v_sender_name TEXT;
    v_receiver_id UUID;
    v_conversation RECORD;
BEGIN
    -- Conversation bilgilerini al
    SELECT * INTO v_conversation
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;
    
    -- Receiver ID belirle
    IF v_conversation.user_id = NEW.sender_id THEN
        v_receiver_id := v_conversation.other_user_id;
    ELSE
        v_receiver_id := v_conversation.user_id;
    END IF;
    
    -- Sender ismini al
    SELECT COALESCE(full_name, username, 'Birisi') INTO v_sender_name
    FROM profiles
    WHERE id = NEW.sender_id;
    
    -- Notifications tablosuna ekle (send_push_on_notification trigger otomatik push gonderir)
    BEGIN
        INSERT INTO notifications (
            user_id,
            type,
            title,
            content,
            actor_id,
            actor_name,
            entity_id,
            is_read
        ) VALUES (
            v_receiver_id,
            'message',
            v_sender_name,
            CASE
                WHEN length(NEW.content) > 100 THEN substring(NEW.content, 1, 100) || '...'
                ELSE NEW.content
            END,
            NEW.sender_id,
            v_sender_name,
            NEW.conversation_id::text,
            FALSE
        );
    EXCEPTION WHEN OTHERS THEN
        -- Notifications INSERT basarisiz olsa bile mesaj gonderimi basarili olsun
        RAISE LOG 'Notification INSERT failed: %', SQLERRM;
    END;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 4. Trigger olustur
DROP TRIGGER IF EXISTS notify_new_message_push_trigger ON messages;
CREATE TRIGGER notify_new_message_push_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_message_push();

-- 5. Sonuc
DO $$
BEGIN
    RAISE NOTICE 'PUSH NOTIFICATION EKLENDI';
    RAISE NOTICE '1. Check constraint kaldirildi (type serbest)';
    RAISE NOTICE '2. notify_new_message_push trigger olusturuldu';
    RAISE NOTICE '3. Mesaj gonderiminde push calisacak';
END $$;

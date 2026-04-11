-- =============================================
-- Tüm Chat Düzeltmeleri - Tek Seferde Çalıştır
-- =============================================

-- 1. Eski UNIQUE INDEX'i sil (conversations_unique_pair)
DROP INDEX IF EXISTS conversations_unique_pair;

-- 2. Trigger'ları temizle
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP TRIGGER IF EXISTS on_new_message_notify ON messages;

-- 3. Mesaj trigger fonksiyonunu güncelle
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_other_user_id UUID;
BEGIN
    -- Gönderenin konuşmasından diğer kullanıcıyı bul
    SELECT other_user_id INTO v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    -- Eğer other_user_id bulunamadıysa, işlemi durdur
    IF v_other_user_id IS NULL THEN
        RAISE WARNING 'Conversation not found for id: %', NEW.conversation_id;
        RETURN NEW;
    END IF;

    -- Gönderenin konuşmasını güncelle
    UPDATE conversations
    SET 
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;

    -- Alıcının konuşmasını oluştur veya güncelle
    INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at)
    VALUES (v_other_user_id, NEW.sender_id, NEW.content, NEW.created_at, 1, NOW(), NOW())
    ON CONFLICT (user_id, other_user_id)
    DO UPDATE SET
        last_message = EXCLUDED.last_message,
        last_message_time = EXCLUDED.last_message_time,
        unread_count = conversations.unread_count + 1,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Trigger'ı oluştur
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- 5. mark_messages_as_read fonksiyonunu düzelt
CREATE OR REPLACE FUNCTION mark_messages_as_read(p_conversation_id UUID)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    
    -- Mesajları okundu olarak işaretle (kullanıcının aldığı mesajlar)
    UPDATE messages
    SET is_read = TRUE, updated_at = NOW()
    WHERE conversation_id = p_conversation_id
    AND sender_id != v_user_id
    AND is_read = FALSE;
    
    -- Kullanıcının kendi konuşmasındaki unread_count'u sıfırla
    -- NOT: İki yönlü sistemde kullanıcının konuşması user_id = currentUserId ile tutulur
    UPDATE conversations
    SET unread_count = 0, updated_at = NOW()
    WHERE id = p_conversation_id
    AND user_id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 6. Doğrulama
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'conversations_unique_pair') THEN
        RAISE EXCEPTION 'conversations_unique_pair index still exists!';
    ELSE
        RAISE NOTICE 'SUCCESS: All chat fixes applied successfully!';
    END IF;
END $$;

-- =====================================================
-- TRIGGER'ı DÜZGÜN GERİ EKLE
-- Sorunlu UUID cast'lerini kullanmadan
-- =====================================================

-- Önce conversations tablosunun tiplerini kontrol et
-- conversations.user_id ve other_user_id UUID mi?
DO $$
BEGIN
    RAISE NOTICE 'Trigger eklemeden önce: conversations user_id tipini kontrol et';
END $$;

SELECT user_id, pg_typeof(user_id) as type, 
       other_user_id, pg_typeof(other_user_id) as type2
FROM public.conversations
LIMIT 1;

-- Trigger fonksiyonu - GÜVENLİ VERSİYON
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_other_user_id UUID;
BEGIN
    -- Diğer kullanıcıyı bul - HER İKİ SÜTUN DA UUID
    SELECT other_user_id INTO v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    IF v_other_user_id IS NULL THEN
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
    -- SÜTUNLAR ZATEN UUID, CAST'E GEREK YOK
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

-- Trigger'ı oluştur
DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- updated_at trigger'ı da ekle
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER messages_updated_at
    BEFORE UPDATE ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DO $$
BEGIN
    RAISE NOTICE '✅ Trigger düzgün şekilde geri eklendi!';
END $$;

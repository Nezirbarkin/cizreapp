-- ============================================================================
-- KONUŞMA SİSTEMİNİ DÜZELT
-- ============================================================================
-- Her mesaj geldiğinde her iki tarafın da conversation kaydı güncellenecek.
-- Karşı tarafa gönderilen mesajda sadece alıcının unread_count'u artırılacak.

-- Mevcut trigger ve fonksiyonu kaldır
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP FUNCTION IF EXISTS update_conversation_on_message();

-- Yeni fonksiyon: Her iki tarafın conversation'ını güncelle
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    conv_other_user_id UUID;
    sender_id UUID := NEW.sender_id;
BEGIN
    -- Konuşmanın other_user_id'sini al (bu karşı tarafın ID'si)
    SELECT other_user_id INTO conv_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;

    -- Gönderen tarafın conversation'ını güncelle (unread_count artmaz)
    UPDATE conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW()
    WHERE user_id = sender_id 
      AND other_user_id = conv_other_user_id;

    -- Alıcı tarafın conversation'ını güncelle veya oluştur (unread_count artar)
    INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count)
    VALUES (conv_other_user_id, sender_id, NEW.content, NEW.created_at, 1)
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
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- Unique constraint ekle (eğer yoksa)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'conversations_user_other_unique'
    ) THEN
        ALTER TABLE conversations ADD CONSTRAINT conversations_user_other_unique UNIQUE (user_id, other_user_id);
    END IF;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON FUNCTION update_conversation_on_message() IS 'Yeni mesajda her iki tarafın conversation kaydını günceller';

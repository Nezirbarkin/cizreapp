-- ============================================================================
-- BASİT MESAJ TRİGGER
-- ============================================================================
-- Mesaj gönderildiğinde:
-- 1. Gönderen tarafın conversation kaydını güncelle
-- 2. Alıcı tarafın conversation kaydını güncelle veya oluştur (unread_count artır)

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

-- Mevcut trigger'ları kaldır
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP TRIGGER IF EXISTS on_new_message_notify ON messages;
DROP FUNCTION IF EXISTS update_conversation_on_message();
DROP FUNCTION IF EXISTS notify_new_message();

-- Yeni basit trigger fonksiyonu
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_other_user_id UUID;
BEGIN
    -- Gönderen tarafın conversation'ından alıcı id'sini bul
    SELECT other_user_id INTO v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;

    -- 1. Gönderen tarafın kaydını güncelle (unread_count artmaz)
    UPDATE conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;

    -- 2. Alıcı tarafın kaydını güncelle veya oluştur (unread_count artar)
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
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

COMMENT ON FUNCTION update_conversation_on_message() IS 'Her mesajda her iki tarafın conversation kaydını günceller';

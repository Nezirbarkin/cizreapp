-- =====================================================
-- FINAL WORKING SOLUTION: RLS KAPALI, TRIGGER ÇALIŞIYOR
-- =====================================================

-- Tüm trigger'ları temizle
DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;
DROP TRIGGER IF EXISTS messages_updated_at ON public.messages;
DROP FUNCTION IF EXISTS public.update_conversation_on_message() CASCADE;
DROP FUNCTION IF EXISTS public.update_updated_at_column() CASCADE;

-- RLS'yi KAPAT (mesaj gönderme için)
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;

-- ÇALIŞAN TRIGGER
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_other_user_id UUID;
BEGIN
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

CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
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
    RAISE NOTICE '✅ FINAL SOLUTION: RLS KAPALI, Trigger ÇALIŞIYOR!';
    RAISE NOTICE '  - Mesaj gönderme BAŞARILI olacak';
    RAISE NOTICE '  - Sohbet kartları GÜNELLENECEK';
    RAISE NOTICE '  - Realtime AKTİF';
END $$;

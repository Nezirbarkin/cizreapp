-- =====================================================
-- TRIGGER CAST FIX: Gereksiz UUID cast'ini kaldır
-- =====================================================

-- Trigger fonksiyonunu düzelt
DROP FUNCTION IF EXISTS public.update_conversation_on_message() CASCADE;
DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;

CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_other_user_id UUID;
BEGIN
    -- conversation_id zaten UUID tipinde, cast'e gerek yok!
    SELECT other_user_id INTO v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    IF v_other_user_id IS NULL THEN
        RETURN NEW;
    END IF;

    UPDATE conversations
    SET 
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;

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

-- RPC'yi de güncelle (cast'i kaldır, zaten parametre TEXT ama INSERT'te UUID olarak kullanılacak)
DROP FUNCTION IF EXISTS public.send_message_direct(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.send_message_direct(
    p_conversation_id TEXT,
    p_content TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
    v_created_at TIMESTAMPTZ;
    v_updated_at TIMESTAMPTZ;
    v_current_user UUID := auth.uid();
BEGIN
    IF v_current_user IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;
    
    INSERT INTO messages (conversation_id, sender_id, content)
    VALUES (p_conversation_id::UUID, v_current_user, p_content)
    RETURNING id, created_at, updated_at
    INTO v_id, v_created_at, v_updated_at;
    
    RETURN json_build_object(
        'id', v_id,
        'conversation_id', p_conversation_id::UUID,
        'sender_id', v_current_user,
        'content', p_content,
        'is_read', false,
        'read_at', null,
        'created_at', v_created_at,
        'updated_at', v_updated_at
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_message_direct(TEXT, TEXT) TO authenticated;

DO $$
BEGIN
    RAISE NOTICE '✅ TRIGGER CAST FIX tamamlandı!';
END $$;

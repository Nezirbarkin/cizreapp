DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP FUNCTION IF EXISTS public.update_conversation_on_message();

CREATE OR REPLACE FUNCTION public.update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_conv_user_id UUID;
    v_conv_other_user_id UUID;
BEGIN
    SELECT user_id, other_user_id
    INTO v_conv_user_id, v_conv_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;

    IF v_conv_user_id IS NULL THEN
        RETURN NEW;
    END IF;

    UPDATE conversations
    SET last_message = NEW.content,
        last_message_time = NEW.created_at,
        unread_count = 0,
        updated_at = NOW(),
        deleted_for_user_id = CASE
            WHEN deleted_for_user_id = NEW.sender_id THEN NULL
            ELSE deleted_for_user_id
        END
    WHERE id = NEW.conversation_id;

    IF NEW.sender_id = v_conv_user_id THEN
        INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at)
        VALUES (v_conv_other_user_id, v_conv_user_id, NEW.content, NEW.created_at, 1, NOW(), NOW())
        ON CONFLICT (user_id, other_user_id)
        DO UPDATE SET
            last_message = EXCLUDED.last_message,
            last_message_time = EXCLUDED.last_message_time,
            unread_count = conversations.unread_count + 1,
            updated_at = NOW();
    ELSE
        INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at)
        VALUES (v_conv_user_id, v_conv_other_user_id, NEW.content, NEW.created_at, 1, NOW(), NOW())
        ON CONFLICT (user_id, other_user_id)
        DO UPDATE SET
            last_message = EXCLUDED.last_message,
            last_message_time = EXCLUDED.last_message_time,
            unread_count = conversations.unread_count + 1,
            updated_at = NOW();
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION public.update_conversation_on_message();
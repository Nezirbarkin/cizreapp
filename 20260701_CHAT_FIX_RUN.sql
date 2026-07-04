ALTER TABLE public.conversations
    ADD COLUMN IF NOT EXISTS deleted_for_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS deleted_for_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_conversations_deleted_for_user_id
    ON public.conversations(deleted_for_user_id);

CREATE INDEX IF NOT EXISTS idx_messages_deleted_for_user_id
    ON public.messages(deleted_for_user_id);

DROP FUNCTION IF EXISTS public.delete_conversation_for_user(UUID);

CREATE OR REPLACE FUNCTION public.delete_conversation_for_user(
    p_conversation_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_other_user_id UUID;
    v_caller UUID := auth.uid();
BEGIN
    SELECT user_id, other_user_id
    INTO v_user_id, v_other_user_id
    FROM conversations
    WHERE id = p_conversation_id;

    IF v_user_id IS NULL THEN
        RETURN false;
    END IF;

    IF v_caller IS NULL OR
       (v_caller != v_user_id AND v_caller != v_other_user_id) THEN
        RETURN false;
    END IF;

    UPDATE conversations
    SET deleted_for_user_id = v_caller
    WHERE id = p_conversation_id;

    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_conversation_for_user(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.delete_conversation_for_user(UUID) FROM anon;

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
    SET
        last_message = NEW.content,
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

DROP FUNCTION IF EXISTS public.mark_sender_messages_read(UUID, UUID);
DROP FUNCTION IF EXISTS public.mark_sender_messages_read(UUID);

CREATE OR REPLACE FUNCTION public.mark_sender_messages_read(
    p_conversation_id UUID,
    p_reader_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_reader_id IS NULL THEN
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM conversations
        WHERE id = p_conversation_id
          AND (user_id = p_reader_id OR other_user_id = p_reader_id)
    ) THEN
        RETURN;
    END IF;

    UPDATE messages
    SET is_read = TRUE, updated_at = NOW()
    WHERE conversation_id = p_conversation_id
      AND sender_id = p_reader_id
      AND is_read = FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_sender_messages_read(UUID, UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_sender_messages_read(UUID, UUID) FROM anon;

DROP FUNCTION IF EXISTS public.mark_messages_as_read(UUID);

CREATE OR REPLACE FUNCTION public.mark_messages_as_read(
    p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reader UUID := auth.uid();
BEGIN
    IF v_reader IS NULL THEN
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM conversations
        WHERE id = p_conversation_id
          AND (user_id = v_reader OR other_user_id = v_reader)
    ) THEN
        RETURN;
    END IF;

    UPDATE messages
    SET is_read = TRUE, updated_at = NOW()
    WHERE conversation_id = p_conversation_id
      AND sender_id != v_reader
      AND is_read = FALSE;

    UPDATE conversations
    SET unread_count = 0, updated_at = NOW()
    WHERE id = p_conversation_id
      AND (user_id = v_reader OR other_user_id = v_reader);
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_messages_as_read(UUID) FROM anon;

DROP TRIGGER IF EXISTS notify_direct_message_trigger ON messages;
DROP FUNCTION IF EXISTS public.notify_direct_message();

CREATE OR REPLACE FUNCTION public.notify_direct_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_recipient_id UUID;
    v_sender_name TEXT;
    v_function_url TEXT;
    v_anon_key TEXT;
    v_request_id BIGINT;
BEGIN
    SELECT
        CASE
            WHEN user_id = NEW.sender_id THEN other_user_id
            WHEN other_user_id = NEW.sender_id THEN user_id
            ELSE NULL
        END
    INTO v_recipient_id
    FROM conversations
    WHERE id = NEW.conversation_id
    LIMIT 1;

    IF v_recipient_id IS NULL THEN
        RAISE LOG 'Direct message: recipient not found for conversation=%', NEW.conversation_id;
        RETURN NEW;
    END IF;

    SELECT COALESCE(full_name, username, 'Biri') INTO v_sender_name
    FROM profiles
    WHERE id = NEW.sender_id;

    v_function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
    v_anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';

    BEGIN
        SELECT net.http_post(
            v_function_url,
            jsonb_build_object(
                'user_id', v_recipient_id::text,
                'title', v_sender_name,
                'body', LEFT(NEW.content, 100),
                'data', jsonb_build_object(
                    'type', 'chat',
                    'conversation_id', NEW.conversation_id::text,
                    'message_id', NEW.id::text
                )
            ),
            '{}'::jsonb,
            jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || v_anon_key
            ),
            5000
        ) INTO v_request_id;

        RAISE LOG 'Direct message push sent: request_id=% to=%', v_request_id, v_recipient_id;
    EXCEPTION WHEN OTHERS THEN
        RAISE LOG 'Direct message push failed: %', SQLERRM;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_direct_message_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_direct_message();

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'conversations'
          AND policyname = 'conversations_update_own'
    ) THEN
        CREATE POLICY "conversations_update_own"
            ON public.conversations
            FOR UPDATE
            TO authenticated
            USING (user_id = auth.uid() OR other_user_id = auth.uid())
            WITH CHECK (user_id = auth.uid() OR other_user_id = auth.uid());
    END IF;
END $$;
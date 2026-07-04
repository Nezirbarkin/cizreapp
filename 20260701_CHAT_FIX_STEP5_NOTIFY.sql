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
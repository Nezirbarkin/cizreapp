DROP FUNCTION IF EXISTS public.mark_sender_messages_read(UUID, UUID);
DROP FUNCTION IF EXISTS public.mark_sender_messages_read(UUID);

CREATE OR REPLACE FUNCTION public.mark_sender_messages_read(p_conversation_id UUID, p_reader_id UUID)
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

CREATE OR REPLACE FUNCTION public.mark_messages_as_read(p_conversation_id UUID)
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
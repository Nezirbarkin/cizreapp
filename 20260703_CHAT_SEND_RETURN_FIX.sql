-- ============================================================================
-- MIGRATION: 20260703_CHAT_SEND_RETURN_FIX.sql
-- -----------------------------------------------------------------------------
-- SORUN (Bug A): send_message_with_recipient RPC'si RETURNS TABLE icinde
--   created_at DONDURMUYORDU. Client tarafinda Message.fromMap, created_at
--   olmadigi icin FormatException firlatiyor -> sendMessage null donuyor ->
--   mesaj DB'ye yazilmasina/realtime ile gelmesine ragmen kullaniciya
--   "Mesaj gonderilemedi" hatasi gosteriliyordu ("1 gonderiyor 1 hata veriyor").
--
-- COZUM: RPC artik created_at, is_read ve reply alanlarini da donduruyor.
--   Ayrica gonderenin kendi kopyasi is_read=FALSE olarak donuyor ki gonderen
--   mesaji atar atmaz "okundu" (mavi tik) gormesin; karsi taraf okuyunca
--   guncellenecek.
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.send_message_with_recipient(UUID, TEXT, UUID, UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.send_message_with_recipient(
    p_conversation_id UUID,
    p_content TEXT,
    p_sender_id UUID,
    p_reply_to_id UUID DEFAULT NULL,
    p_reply_to_content TEXT DEFAULT NULL,
    p_reply_to_sender_name TEXT DEFAULT NULL
)
RETURNS TABLE (
    message_id UUID,
    sender_id UUID,
    recipient_id UUID,
    recipient_message_id UUID,
    content TEXT,
    conversation_id UUID,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    is_read BOOLEAN,
    reply_to_id UUID,
    reply_to_content TEXT,
    reply_to_sender_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_conv_user_id UUID;
    v_conv_other_user_id UUID;
    v_recipient_id UUID;
    v_recipient_conv_id UUID;
    v_new_message_id UUID;
    v_recipient_message_id UUID;
    v_now TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    SELECT c.user_id, c.other_user_id
    INTO v_conv_user_id, v_conv_other_user_id
    FROM conversations c
    WHERE c.id = p_conversation_id;

    IF v_conv_user_id IS NULL THEN
        RAISE EXCEPTION 'Conversation not found';
    END IF;

    IF v_conv_user_id != p_sender_id THEN
        RAISE EXCEPTION 'Only conversation owner can send messages';
    END IF;

    v_recipient_id := v_conv_other_user_id;

    SELECT c.id INTO v_recipient_conv_id
    FROM conversations c
    WHERE c.user_id = v_recipient_id
      AND c.other_user_id = p_sender_id;

    -- 1) Gonderenin conversation'una mesaj ekle (is_read=true: gonderen zaten okumus)
    INSERT INTO messages (conversation_id, sender_id, content, is_read, created_at, updated_at, reply_to_id, reply_to_content, reply_to_sender_name)
    VALUES (p_conversation_id, p_sender_id, p_content, TRUE, v_now, v_now, p_reply_to_id, p_reply_to_content, p_reply_to_sender_name)
    RETURNING id INTO v_new_message_id;

    UPDATE conversations
    SET
        last_message = p_content,
        last_message_time = v_now,
        unread_count = 0,
        updated_at = v_now
    WHERE id = p_conversation_id;

    -- 2) Alicinin conversation'una da ayni mesaji ekle (is_read=false)
    IF v_recipient_conv_id IS NOT NULL THEN
        INSERT INTO messages (conversation_id, sender_id, content, is_read, created_at, updated_at, reply_to_id, reply_to_content, reply_to_sender_name)
        VALUES (v_recipient_conv_id, p_sender_id, p_content, FALSE, v_now, v_now, p_reply_to_id, p_reply_to_content, p_reply_to_sender_name)
        RETURNING id INTO v_recipient_message_id;

        UPDATE conversations
        SET
            last_message = p_content,
            last_message_time = v_now,
            unread_count = unread_count + 1,
            updated_at = v_now
        WHERE id = v_recipient_conv_id;
    ELSE
        INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at)
        VALUES (v_recipient_id, p_sender_id, p_content, v_now, 1, v_now, v_now)
        RETURNING id INTO v_recipient_conv_id;

        INSERT INTO messages (conversation_id, sender_id, content, is_read, created_at, updated_at, reply_to_id, reply_to_content, reply_to_sender_name)
        VALUES (v_recipient_conv_id, p_sender_id, p_content, FALSE, v_now, v_now, p_reply_to_id, p_reply_to_content, p_reply_to_sender_name)
        RETURNING id INTO v_recipient_message_id;
    END IF;

    RETURN QUERY
    SELECT
        v_new_message_id,
        p_sender_id,
        v_recipient_id,
        v_recipient_message_id,
        p_content,
        p_conversation_id,
        v_now,                       -- created_at (Bug A fix)
        v_now,                       -- updated_at
        FALSE,                       -- is_read: gonderen icin karsi taraf henuz okumadi
        p_reply_to_id,
        p_reply_to_content,
        p_reply_to_sender_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_message_with_recipient(UUID, TEXT, UUID, UUID, TEXT, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.send_message_with_recipient(UUID, TEXT, UUID, UUID, TEXT, TEXT) FROM anon;

NOTIFY pgrst, 'reload schema';

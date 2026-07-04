-- ============================================================================
-- MIGRATION: 20260702_CHAT_REALTIME_FIX_V2.sql
-- -----------------------------------------------------------------------------
-- AMAC: Mesajlarin karsi tarafa düsmesini saglamak (Sorun #1)
--
-- ESKI SISTEM (54001 HATASI):
--   - Trigger iceinde messages tablosuna INSERT yapiliyordu
--   - Bu INSERT trigger'i tekrar tetikliyordu, sonsuz dongu
--
-- YENI SISTEM:
--   - Trigger SADECE conversations tablosunu guncelleyir (messages'a INSERT YOK)
--   - Mesajlarin her iki conversation'a eklenmesi RPC iceinde yapilir
--   - RPC tek cagrida iki mesaj satiri olusturur
-- -----------------------------------------------------------------------------

-- ADIM 1: Eski trigger'i tamamen kaldir
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP FUNCTION IF EXISTS public.update_conversation_on_message();


-- ADIM 2: Yeni basit trigger (SADECE conversations guncelleyir)
CREATE OR REPLACE FUNCTION public.update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_conv_user_id UUID;
    v_conv_other_user_id UUID;
    v_recipient_id UUID;
BEGIN
    SELECT user_id, other_user_id
    INTO v_conv_user_id, v_conv_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;

    IF v_conv_user_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.sender_id = v_conv_user_id THEN
        v_recipient_id := v_conv_other_user_id;
    ELSE
        v_recipient_id := v_conv_user_id;
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

    INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at)
    VALUES (v_recipient_id, NEW.sender_id, NEW.content, NEW.created_at, 1, NOW(), NOW())
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
    EXECUTE FUNCTION public.update_conversation_on_message();

GRANT EXECUTE ON FUNCTION public.update_conversation_on_message() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.update_conversation_on_message() FROM anon;


-- ADIM 3: Yeni RPC - Mesaji her iki conversation'a da ekler
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
    conversation_id UUID
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
    SELECT user_id, other_user_id
    INTO v_conv_user_id, v_conv_other_user_id
    FROM conversations
    WHERE id = p_conversation_id;

    IF v_conv_user_id IS NULL THEN
        RAISE EXCEPTION 'Conversation not found';
    END IF;

    IF v_conv_user_id != p_sender_id THEN
        RAISE EXCEPTION 'Only conversation owner can send messages';
    END IF;

    v_recipient_id := v_conv_other_user_id;

    SELECT id INTO v_recipient_conv_id
    FROM conversations
    WHERE user_id = v_recipient_id
      AND other_user_id = p_sender_id;

    -- 1) Gonderenin conversation'una mesaj ekle (is_read=true)
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
        p_conversation_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_message_with_recipient(UUID, TEXT, UUID, UUID, TEXT, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.send_message_with_recipient(UUID, TEXT, UUID, UUID, TEXT, TEXT) FROM anon;


-- ADIM 4: Dogrulama
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM pg_proc
    WHERE proname = 'send_message_with_recipient'
      AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

    IF v_count > 0 THEN
        RAISE NOTICE '===========================================';
        RAISE NOTICE 'BASARILI: send_message_with_recipient RPC olusturuldu';
        RAISE NOTICE '===========================================';
    ELSE
        RAISE EXCEPTION 'HATA: RPC olusturulamadi!';
    END IF;
END $$;

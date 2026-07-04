-- ============================================================================
-- MIGRATION: 20260703_CHAT_UNREAD_BADGE_FIX.sql
-- -----------------------------------------------------------------------------
-- SORUN: A, B'ye mesaj atınca B'nin okunmamış rozeti (yüzen mesaj ikonu +
--   sohbet kartı) görünmüyordu.
--
-- KÖK NEDEN (çift yönetim):
--   send_message_with_recipient RPC'si conversations.unread_count'u güncelliyordu
--   AMA message_insert_trigger (update_conversation_on_message) da HER messages
--   INSERT'inde conversations'ı güncelliyordu. Mailbox modelinde RPC her mesaj
--   için İKİ satır yazıyor; eski trigger koşulsuz olarak NEW.conversation_id'nin
--   unread'ini 0 yapıp KARŞI tarafı +1 artırıyordu. Alıcının kopyası (row2,
--   conv sahibi = alıcı, sender = gönderen) eklendiğinde trigger alıcının
--   conv'unu 0'a çekiyor + yanlış conv'u artırıyordu → B'nin badge'i 0 kalıyordu.
--
-- ÇÖZÜM (tek yetkili kaynak = TRIGGER, satır-bazlı):
--   1) RPC artık conversations'ı GÜNCELLEMİYOR — sadece iki messages satırı ekler
--      ve gerekiyorsa alıcı conv'unu unread=0 ile oluşturur.
--   2) Trigger her satır için conv'un SAHİBİNE bakar:
--        - NEW.sender_id = conv.user_id  → sahip GÖNDERDİ  → unread=0
--        - NEW.sender_id ≠ conv.user_id  → sahip ALDI       → unread += 1
--      Yalnızca NEW.conversation_id güncellenir (çapraz artırım YOK). Mailbox
--      modelinde her conv'a zaten ayrı satır düştüğü için bu yeterli ve doğru.
--      Ayrıca yeni mesaj, ilgili taraf için soft-delete'i geri alır.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) TRIGGER: tek yetkili conversations güncelleyici
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_owner UUID;
BEGIN
    SELECT user_id INTO v_owner
    FROM conversations
    WHERE id = NEW.conversation_id;

    IF v_owner IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.sender_id = v_owner THEN
        -- Bu conv'un sahibi mesajı GÖNDERDİ → okunmuş say
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
    ELSE
        -- Bu conv'un sahibi mesajı ALDI → okunmamış +1
        UPDATE conversations
        SET last_message = NEW.content,
            last_message_time = NEW.created_at,
            unread_count = COALESCE(unread_count, 0) + 1,
            updated_at = NOW(),
            deleted_for_user_id = CASE
                WHEN deleted_for_user_id = v_owner THEN NULL  -- alıcı silmişti → geri getir
                ELSE deleted_for_user_id
            END
        WHERE id = NEW.conversation_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION public.update_conversation_on_message();

GRANT EXECUTE ON FUNCTION public.update_conversation_on_message() TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) RPC: yalnızca mesaj satırlarını ekle (conversations'a DOKUNMA)
-- ---------------------------------------------------------------------------
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

    -- Alıcı conv'u yoksa oluştur (unread=0; trigger row2'de +1 yapacak)
    IF v_recipient_conv_id IS NULL THEN
        INSERT INTO conversations (user_id, other_user_id, unread_count, created_at, updated_at)
        VALUES (v_recipient_id, p_sender_id, 0, v_now, v_now)
        RETURNING id INTO v_recipient_conv_id;
    END IF;

    -- 1) Gönderenin kopyası (is_read=TRUE) → trigger: gönderen conv unread=0
    INSERT INTO messages (conversation_id, sender_id, content, is_read, created_at, updated_at, reply_to_id, reply_to_content, reply_to_sender_name)
    VALUES (p_conversation_id, p_sender_id, p_content, TRUE, v_now, v_now, p_reply_to_id, p_reply_to_content, p_reply_to_sender_name)
    RETURNING id INTO v_new_message_id;

    -- 2) Alıcının kopyası (is_read=FALSE) → trigger: alıcı conv unread += 1
    INSERT INTO messages (conversation_id, sender_id, content, is_read, created_at, updated_at, reply_to_id, reply_to_content, reply_to_sender_name)
    VALUES (v_recipient_conv_id, p_sender_id, p_content, FALSE, v_now, v_now, p_reply_to_id, p_reply_to_content, p_reply_to_sender_name)
    RETURNING id INTO v_recipient_message_id;

    RETURN QUERY
    SELECT
        v_new_message_id,
        p_sender_id,
        v_recipient_id,
        v_recipient_message_id,
        p_content,
        p_conversation_id,
        v_now,
        v_now,
        FALSE,
        p_reply_to_id,
        p_reply_to_content,
        p_reply_to_sender_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_message_with_recipient(UUID, TEXT, UUID, UUID, TEXT, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.send_message_with_recipient(UUID, TEXT, UUID, UUID, TEXT, TEXT) FROM anon;

NOTIFY pgrst, 'reload schema';

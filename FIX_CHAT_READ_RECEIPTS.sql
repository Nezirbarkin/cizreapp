-- ==============================================================================
-- FIX: Chat Mesaj Okundu Bilgisi ve Sohbet Listesi Görünme Sorunu
-- ==============================================================================
-- Bu SQL aşağıdaki sorunları çözer:
-- 1. Sohbet listesinde karşı tarafın başlattığı sohbetler görünmüyor
-- 2. Mavi çift tik (okundu) hiç görünmüyor
-- 3. Mesajlar eksik veya hiç gözükmüyor
-- ==============================================================================

-- ============================================================================
-- 1. mark_messages_as_read: Hem benim hem karşı tarafın conversation'ındaki
--    bana gelen mesajları okundu yap
-- ============================================================================
CREATE OR REPLACE FUNCTION public.mark_messages_as_read(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_other_user_id UUID;
    v_other_conv_id UUID;
BEGIN
    v_current_user_id := auth.uid();
    IF v_current_user_id IS NULL THEN
        RETURN;
    END IF;

    -- Bu conversation'ın diğer tarafını bul
    SELECT user_id, other_user_id INTO v_current_user_id, v_other_user_id
    FROM conversations
    WHERE id = p_conversation_id;

    -- Eğer user_id bana ait değilse, bu conversation benim tarafıma ait değil demektir
    -- Bu durumda v_current_user_id'yi other_user_id olarak kabul et
    IF v_current_user_id = auth.uid() THEN
        -- p_conversation_id benim conversation'ım
        v_other_user_id := (
            SELECT other_user_id FROM conversations WHERE id = p_conversation_id
        );
    ELSE
        -- p_conversation_id karşı tarafın conversation'ı, ben other_user_id'im
        v_current_user_id := (
            SELECT user_id FROM conversations WHERE id = p_conversation_id
        );
        v_other_user_id := (
            SELECT other_user_id FROM conversations WHERE id = p_conversation_id
        );
    END IF;

    -- Karşı tarafın conversation_id'sini bul
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
    AND other_user_id = v_current_user_id;

    -- Her iki conversation'daki bana gelen mesajları okundu yap
    IF v_other_conv_id IS NOT NULL THEN
        UPDATE messages
        SET is_read = true, updated_at = NOW()
        WHERE conversation_id IN (p_conversation_id, v_other_conv_id)
        AND sender_id != auth.uid()
        AND is_read = false;
    ELSE
        -- Sadece verilen conversation'daki mesajları güncelle
        UPDATE messages
        SET is_read = true, updated_at = NOW()
        WHERE conversation_id = p_conversation_id
        AND sender_id != auth.uid()
        AND is_read = false;
    END IF;

    -- Benim conversation'ımdaki unread_count'u sıfırla
    UPDATE conversations
    SET unread_count = 0, updated_at = NOW()
    WHERE (id = p_conversation_id OR
           (user_id = auth.uid() AND other_user_id = v_other_user_id))
    AND user_id = auth.uid();
END;
$$;

-- ============================================================================
-- 2. mark_sender_messages_read: Karşı taraf sohbeti açtığında benim mesajlarımı
--    okundu yap (her iki conversation'da)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.mark_sender_messages_read(
    p_conversation_id UUID,
    p_reader_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_conv_user_id UUID;
    v_conv_other_user_id UUID;
    v_other_conv_id UUID;
BEGIN
    -- Konuşma bilgilerini al
    SELECT user_id, other_user_id INTO v_conv_user_id, v_conv_other_user_id
    FROM conversations
    WHERE id = p_conversation_id;

    IF v_conv_user_id IS NULL THEN
        RETURN;
    END IF;

    -- Karşı tarafın conversation_id'sini bul
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_conv_other_user_id
    AND other_user_id = v_conv_user_id;

    -- DÜZELTME: Her iki conversation'daki, p_reader_id'nin gönderdiği mesajları
    -- okundu yap (p_reader_id sohbeti açan kişi, yani benim)
    IF v_other_conv_id IS NOT NULL THEN
        UPDATE messages
        SET is_read = true, updated_at = NOW()
        WHERE conversation_id IN (p_conversation_id, v_other_conv_id)
        AND sender_id = p_reader_id
        AND is_read = false;
    ELSE
        UPDATE messages
        SET is_read = true, updated_at = NOW()
        WHERE conversation_id = p_conversation_id
        AND sender_id = p_reader_id
        AND is_read = false;
    END IF;

    -- Okuyucunun kendi conversation'ındaki unread_count'u sıfırla
    UPDATE conversations
    SET unread_count = 0, updated_at = NOW()
    WHERE id = p_conversation_id
    AND user_id = p_reader_id;
END;
$$;

-- ============================================================================
-- 3. update_conversation_on_message: Hem gönderenin hem alıcının conversation'ını
--    güncelle (zaten FIX_CHAT_MESSAGES_FINAL.sql'de yapılmıştı, burada da güvence)
-- ============================================================================
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_conv_user_id UUID;
    v_conv_other_user_id UUID;
    v_other_conv_id UUID;
    v_recipient_id UUID;
    v_sender_name TEXT;
BEGIN
    -- 1. Gönderenin conversation bilgilerini al
    SELECT user_id, other_user_id INTO v_conv_user_id, v_conv_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;

    -- 2. Gönderenin kendi conversation'ını güncelle
    UPDATE conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;

    -- 3. Karşı tarafın conversation'ını bul
    -- Eğer bu conversation user_id=NEW.sender_id ise karşı taraf other_user_id
    -- Eğer bu conversation other_user_id=NEW.sender_id ise karşı taraf user_id
    IF v_conv_user_id = NEW.sender_id THEN
        v_recipient_id := v_conv_other_user_id;
    ELSE
        v_recipient_id := v_conv_user_id;
    END IF;

    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_recipient_id
    AND other_user_id = NEW.sender_id;

    IF v_other_conv_id IS NULL THEN
        -- DÜZELTME: Karşı tarafın conversation'ı yoksa oluştur
        -- (Bu sayede karşı tarafın başlattığı sohbetler de listede görünür)
        INSERT INTO conversations (user_id, other_user_id)
        VALUES (v_recipient_id, NEW.sender_id)
        RETURNING id INTO v_other_conv_id;
    END IF;

    -- 4. Karşı tarafın conversation'ını güncelle (unread_count artır)
    UPDATE conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW(),
        unread_count = unread_count + 1
    WHERE id = v_other_conv_id;

    -- 5. Push notification gönder
    IF v_recipient_id IS NOT NULL THEN
        SELECT full_name INTO v_sender_name
        FROM profiles
        WHERE id = NEW.sender_id;

        IF v_sender_name IS NOT NULL THEN
            BEGIN
                INSERT INTO notifications (user_id, type, title, content, data)
                VALUES (
                    v_recipient_id,
                    'message',
                    v_sender_name,
                    CASE
                        WHEN NEW.content LIKE 'SHARED_POST:%' THEN '📤 Bir gönderi paylaştı'
                        ELSE LEFT(COALESCE(NEW.content, ''), 100)
                    END,
                    jsonb_build_object(
                        'conversation_id', NEW.conversation_id,
                        'sender_id', NEW.sender_id
                    )
                );
            EXCEPTION WHEN OTHERS THEN
                RAISE LOG 'Chat push notification failed: %', SQLERRM;
            END;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- ============================================================================
-- 4. RLS Policies: messages_update hem SELECT hem UPDATE için düzeltme
-- ============================================================================
-- ÖNEMLİ: messages_update_own sadece sender_id=auth.uid() olan mesajları
-- güncelleyebilir, ama karşı tarafın conversation'ındaki mesajları okundu
-- işaretlemek için sender_id != auth.uid() olan mesajları da güncellememiz gerekiyor.
-- Bu yüzden UPDATE policy'sini genişletiyoruz: konuşmanın taraflarından biri olmak yeterli.

DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
CREATE POLICY "messages_update_conversation_participants"
ON public.messages
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
);

-- ============================================================================
-- 5. RLS Policies: messages_select (her iki tarafın mesajlarını görebilsin)
-- ============================================================================
DROP POLICY IF EXISTS "messages_select_own_conversations" ON public.messages;
CREATE POLICY "messages_select_own_conversations"
ON public.messages
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
);

-- ============================================================================
-- 6. Permissions
-- ============================================================================
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_sender_messages_read(UUID, UUID) TO authenticated;

-- Realtime için publications (yoksa ekle)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND tablename = 'messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE messages;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND tablename = 'conversations'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
    END IF;
END $$;

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '✅ Chat okundu bilgisi ve sohbet listesi düzeltildi:';
    RAISE NOTICE '  ✅ mark_messages_as_read her iki conv''ı günceller';
    RAISE NOTICE '  ✅ mark_sender_messages_read her iki conv''ı günceller';
    RAISE NOTICE '  ✅ update_conversation_on_message karşı tarafın conv''ını otomatik oluşturur';
    RAISE NOTICE '  ✅ messages_update policy konuşma katılımcılarına izin verir';
    RAISE NOTICE '  ✅ RLS SELECT her iki tarafın mesajlarını gösterir';
END $$;

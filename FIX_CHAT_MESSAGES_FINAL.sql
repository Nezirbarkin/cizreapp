-- ==============================================================================
-- FIX: Chat RPC Fonksiyonları ve Mesaj Görünme Sorunu
-- ==============================================================================

-- 1. mark_sender_messages_read fonksiyonu oluştur (eksik!)
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
    v_user_id UUID;
    v_other_user_id UUID;
    v_other_conv_id UUID;
BEGIN
    -- Konuşma bilgilerini al
    SELECT user_id, other_user_id INTO v_user_id, v_other_user_id
    FROM conversations
    WHERE id = p_conversation_id;
    
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;
    
    -- Karşı tarafın conversation_id'sini bul
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
    AND other_user_id = v_user_id;
    
    -- Her iki conversation'daki mesajları okundu yap
    -- (p_reader_id olmayan sender'ın mesajları)
    UPDATE messages
    SET is_read = true
    WHERE conversation_id IN (p_conversation_id, v_other_conv_id)
    AND sender_id != p_reader_id
    AND is_read = false;
    
    -- Okuyucunun unread_count'unu sıfırla
    UPDATE conversations
    SET unread_count = 0
    WHERE id = p_conversation_id;
END;
$$;

-- 2. mark_messages_as_read fonksiyonunu güncelle (iki yönlü çalışsın)
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
    -- Konuşma sahibini al
    SELECT user_id, other_user_id INTO v_current_user_id, v_other_user_id
    FROM conversations
    WHERE id = p_conversation_id;
    
    IF v_current_user_id IS NULL THEN
        RETURN;
    END IF;
    
    -- Karşı tarafın conversation_id'sini bul
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
    AND other_user_id = v_current_user_id;
    
    -- Her iki conversation'daki bana gelen mesajları okundu yap
    UPDATE messages
    SET is_read = true
    WHERE conversation_id IN (p_conversation_id, v_other_conv_id)
    AND sender_id != v_current_user_id
    AND is_read = false;
    
    -- Benim unread_count'umu sıfırla
    UPDATE conversations
    SET unread_count = 0
    WHERE id = p_conversation_id;
END;
$$;

-- 3. update_conversation_on_message - HER İKİ TARAFIN conversation'ını güncelle
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
    
    -- 3. Karşı tarafın conversation'ını bul ve güncelle
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_conv_other_user_id
    AND other_user_id = v_conv_user_id;
    
    IF v_other_conv_id IS NOT NULL THEN
        UPDATE conversations
        SET
            last_message = NEW.content,
            last_message_time = NEW.created_at,
            updated_at = NOW(),
            unread_count = CASE
                WHEN user_id != NEW.sender_id THEN unread_count + 1
                ELSE unread_count
            END
        WHERE id = v_other_conv_id;
    END IF;
    
    -- 4. Alıcıyı belirle (sender olmayan taraf)
    IF v_conv_user_id = NEW.sender_id THEN
        v_recipient_id := v_conv_other_user_id;
    ELSE
        v_recipient_id := v_conv_user_id;
    END IF;
    
    -- 5. Gönderenin adını al
    SELECT full_name INTO v_sender_name
    FROM profiles
    WHERE id = NEW.sender_id;
    
    -- 6. Push notification gönder
    IF v_recipient_id IS NOT NULL AND v_sender_name IS NOT NULL THEN
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
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- 4. GRANT permissions
GRANT EXECUTE ON FUNCTION mark_sender_messages_read(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_messages_as_read(UUID) TO authenticated;

DO $$
BEGIN
    RAISE NOTICE '✅ Chat sistemi tamamen düzeltildi:';
    RAISE NOTICE '  ✅ mark_sender_messages_read() fonksiyonu oluşturuldu';
    RAISE NOTICE '  ✅ mark_messages_as_read() fonksiyonu güncellendi';
    RAISE NOTICE '  ✅ update_conversation_on_message() her iki tarafı günceller';
    RAISE NOTICE '  ✅ Push notification mesajlarda çalışır';
END $$;

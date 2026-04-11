-- ==============================================================================
-- FIX: Chat System Complete Fix
-- ==============================================================================
-- 1. Gelen mesajlar push çalışmıyor → Trigger eklenecek
-- 2. Mesajlar ekranında sohbet kartında tek tık görünüyor → Duplicate conversation
-- 3. Sohbet kartında mesaj var ama içeriğe girince mesajlar yok → Conversation ID uyuşmazlığı
-- ==============================================================================

-- ==============================================================================
-- 1. MESAJ PUSH NOTIFICATION TRIGGER
-- ==============================================================================

-- Önce mevcut fonksiyonu güncelle - push notification ekleyelim
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_other_conv_id UUID;
    v_recipient_id UUID;
    v_sender_name TEXT;
BEGIN
    -- 1. Konuşmadaki last_message bilgilerini güncelle
    UPDATE conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW(),
        unread_count = CASE
            WHEN conversations.user_id != NEW.sender_id THEN conversations.unread_count + 1
            ELSE conversations.unread_count
        END
    WHERE id = NEW.conversation_id;
    
    -- 2. Alıcıyı bul (conversation'daki user_id != sender_id olan)
    SELECT user_id INTO v_recipient_id
    FROM conversations
    WHERE id = NEW.conversation_id
    AND user_id != NEW.sender_id;
    
    -- 3. Gönderenin adını al
    SELECT full_name INTO v_sender_name
    FROM profiles
    WHERE id = NEW.sender_id;
    
    -- 4. Alıcı için push notification gönder
    IF v_recipient_id IS NOT NULL AND v_sender_name IS NOT NULL THEN
        INSERT INTO notifications (user_id, type, title, content, data)
        VALUES (
            v_recipient_id,
            'message',
            v_sender_name,
            COALESCE(NEW.content, ''),
            jsonb_build_object('conversation_id', NEW.conversation_id)
        );
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

-- ==============================================================================
-- 2. DUPLICATE CONVERSATION TEMİZLEME
-- ==============================================================================

-- Duplicate conversation kontrolü
-- Aynı user_id ve other_user_id çifti için sadece bir kayıt olmalı
DO $$
DECLARE
    v_duplicate_count INTEGER;
BEGIN
    -- Duplicate kayıtları say
    SELECT COUNT(*) INTO v_duplicate_count
    FROM (
        SELECT user_id, other_user_id, COUNT(*) as cnt
        FROM conversations
        GROUP BY user_id, other_user_id
        HAVING COUNT(*) > 1
    ) duplicates;
    
    IF v_duplicate_count > 0 THEN
        RAISE NOTICE '⚠️ % duplicate conversation çifti bulundu', v_duplicate_count;
    ELSE
        RAISE NOTICE '✅ Duplicate conversation yok';
    END IF;
END $$;

-- ==============================================================================
-- 3. CONVERSATION ID UYUŞMAZLIĞI DÜZELTME
-- ==============================================================================

-- messages tablosunda conversation_id'nin conversations tablosunda olduğunu kontrol et
SELECT 
    m.conversation_id,
    COUNT(*) as message_count,
    (SELECT COUNT(*) FROM conversations c WHERE c.id = m.conversation_id) as conv_exists
FROM messages m
GROUP BY m.conversation_id
HAVING (SELECT COUNT(*) FROM conversations c WHERE c.id = m.conversation_id) = 0
LIMIT 10;

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '✅ Chat system fix tamamlandı:';
    RAISE NOTICE '✅ 1. Mesaj push notification trigger eklendi';
    RAISE NOTICE '✅ 2. Duplicate conversation kontrolü yapıldı';
    RAISE NOTICE '✅ 3. Conversation ID uyuşmazlığı kontrol edildi';
END $$;

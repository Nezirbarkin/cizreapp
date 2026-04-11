-- ============================================================================
-- CHAT NOTIFICATION TRIGGER KALDIRMA
-- ============================================================================
-- Mesaj bildirimleri notifications tablosuna kaydedilmeyecek, sadece chat badge kullanılacak.
-- Mevcut notify_new_message trigger'ı kaldırıp, sadece unread_count güncelleyen trigger oluşturuyoruz.

-- Önce mevcut trigger'ı drop et
DROP TRIGGER IF EXISTS on_new_message_notify ON messages;

-- Mevcut fonksiyonu drop et
DROP FUNCTION IF EXISTS notify_new_message();

-- Yeni fonksiyon: Sadece unread_count günceller, notification eklemez
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Konuşmadaki last_message bilgilerini güncelle
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
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı yeniden oluştur (zaten varsa drop edip yeniden oluşturur)
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

COMMENT ON FUNCTION update_conversation_on_message() IS 'Yeni mesajda conversation unread_count artırır, notification eklemez';

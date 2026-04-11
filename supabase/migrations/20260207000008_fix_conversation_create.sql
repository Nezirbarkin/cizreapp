-- ============================================================================
-- KONUŞMA SİSTEMİ DÜZELTME - Yeni mesajda karşı taraf için conversation oluştur
-- ============================================================================
-- Sorun: Kullanıcı B hiç chat ekranını açmadıysa, conversations tablosunda
-- kaydı yok. Kullanıcı A mesaj attığında B'nin listesinde sohbet görünmüyor.
-- Çözüm: Trigger, karşı taraf için de conversation kaydı oluşturmalı.

-- Mevcut fonksiyonu kaldır ve yeniden oluştur (iki yönlü destek ile)
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP FUNCTION IF EXISTS update_conversation_on_message();

CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    -- Gönderen ve alıcı kullanıcı ID'leri
    v_sender_id UUID := NEW.sender_id;
    v_conv_id UUID := NEW.conversation_id;
    
    -- Mevcut conversation bilgileri
    v_user_id UUID;
    v_other_user_id UUID;
    
    -- Karşı tarafın conversation ID'si
    v_other_conv_id UUID;
BEGIN
    -- Mevcut conversation bilgilerini al
    SELECT user_id, other_user_id INTO v_user_id, v_other_user_id
    FROM conversations
    WHERE id = v_conv_id;
    
    -- Mevcut conversation'ı güncelle
    UPDATE conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW(),
        unread_count = CASE
            -- Karşı taraftan mesaj geldiyse unread_count artır
            WHEN user_id != v_sender_id THEN unread_count + 1
            ELSE unread_count
        END
    WHERE id = v_conv_id;
    
    -- Karşı taraf için conversation var mı kontrol et
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
      AND other_user_id = v_user_id;
    
    -- Karşı taraf için conversation yoksa oluştur
    IF v_other_conv_id IS NULL THEN
        INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count)
        VALUES (v_other_user_id, v_user_id, NEW.content, NEW.created_at, 1);
        
        RAISE NOTICE 'Created conversation for other user: % -> %', v_other_user_id, v_user_id;
    ELSE
        -- Karşı taraf için conversation varsa güncelle
        UPDATE conversations
        SET
            last_message = NEW.content,
            last_message_time = NEW.created_at,
            updated_at = NOW(),
            unread_count = unread_count + 1
        WHERE id = v_other_conv_id;
        
        RAISE NOTICE 'Updated conversation for other user: %', v_other_conv_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger'ı yeniden oluştur
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

COMMENT ON FUNCTION update_conversation_on_message() IS 
'Yeni mesaj geldiğinde hem gönderenin hem de alıcının conversation kaydını günceller veya oluşturur';

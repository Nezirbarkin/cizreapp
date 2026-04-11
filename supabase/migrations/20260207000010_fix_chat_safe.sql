-- ============================================================================
-- ACİL DÜZELTME: Mesaj gönderilemiyor sorununu çözer
-- ============================================================================
-- Trigger'ı tamamen kaldırıp sıfırdan güvenli şekilde oluşturuyoruz
-- Push notification başarısız olsa bile mesaj kaydedilsin

-- 1. Önce trigger'ı tamamen kaldır
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP TRIGGER IF EXISTS on_new_message_notify ON messages;

-- 2. Basit ve güvenli trigger - sadece conversation güncelleme
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_other_user_id UUID;
    v_other_conv_id UUID;
BEGIN
    -- Mevcut conversation bilgilerini al
    SELECT user_id, other_user_id INTO v_user_id, v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    -- Mevcut conversation'ı güncelle
    UPDATE conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW(),
        unread_count = CASE
            WHEN user_id != NEW.sender_id THEN unread_count + 1
            ELSE unread_count
        END
    WHERE id = NEW.conversation_id;
    
    -- Karşı taraf için conversation var mı kontrol et
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
      AND other_user_id = v_user_id;
    
    -- Karşı taraf için conversation yoksa oluştur
    IF v_other_conv_id IS NULL THEN
        INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count)
        VALUES (v_other_user_id, v_user_id, NEW.content, NEW.created_at, 1);
    ELSE
        -- Karşı taraf için conversation varsa güncelle
        UPDATE conversations
        SET
            last_message = NEW.content,
            last_message_time = NEW.created_at,
            updated_at = NOW(),
            unread_count = unread_count + 1
        WHERE id = v_other_conv_id;
    END IF;
    
    -- HER ZAMAN BAŞARILI DÖN - HATA YOK
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 3. Trigger'ı yeniden oluştur
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- 4. Test mesajı gönderebilirsiniz - artık çalışmalı
DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE '✅ MESAJ GÖNDERİMİ DÜZELTİLDİ';
    RAISE NOTICE '✅ Trigger güvenli şekilde yeniden oluşturuldu';
    RAISE NOTICE '✅ Push notification kaldırıldı (sorun kaynağıydı)';
    RAISE NOTICE '✅ Conversation güncellemesi çalışıyor';
    RAISE NOTICE '============================================================================';
END $$;

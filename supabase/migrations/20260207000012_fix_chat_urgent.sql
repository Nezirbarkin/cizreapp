-- ============================================================================
-- ACİL DÜZELTME: Mesaj gönderilemiyor sorunu
-- ============================================================================
-- Sorun: conversations_unique_pair index'i A-B ve B-A aynı kabul ediyor
-- Bu yüzden karşı taraf için INSERT yapmak hata veriyor

-- 1. Unique index'i kaldır (çift yönlü conversation oluşturmaya engel oluyor)
DROP INDEX IF EXISTS conversations_unique_pair;

-- 2. Yerine user_id + other_user_id unique constraint koy
CREATE UNIQUE INDEX IF NOT EXISTS conversations_user_other_unique
ON conversations(user_id, other_user_id);

-- 3. Fonksiyonu güncelle (basit ve güvenli)
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
    
    -- Mevcut conversation guncelle
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
    
    -- Karsi taraf icin conversation var mi kontrol et
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
      AND other_user_id = v_user_id;
    
    -- Karsi taraf icin conversation yoksa olustur
    IF v_other_conv_id IS NULL THEN
        BEGIN
            INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count)
            VALUES (v_other_user_id, v_user_id, NEW.content, NEW.created_at, 1);
        EXCEPTION WHEN unique_violation THEN
            -- Zaten varsa guncelle
            UPDATE conversations
            SET
                last_message = NEW.content,
                last_message_time = NEW.created_at,
                updated_at = NOW(),
                unread_count = unread_count + 1
            WHERE user_id = v_other_user_id
              AND other_user_id = v_user_id;
        END;
    ELSE
        -- Karsi taraf icin conversation varsa guncelle
        UPDATE conversations
        SET
            last_message = NEW.content,
            last_message_time = NEW.created_at,
            updated_at = NOW(),
            unread_count = unread_count + 1
        WHERE id = v_other_conv_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 4. Trigger kontrol
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- 5. Sonuc
DO $$
BEGIN
    RAISE NOTICE 'DUZELTME TAMAMLANDI';
    RAISE NOTICE '1. conversations_unique_pair index kaldirildi';
    RAISE NOTICE '2. conversations_user_other_unique index eklendi';
    RAISE NOTICE '3. Fonksiyon guncellendi (exception handling ile)';
    RAISE NOTICE '4. Trigger yeniden olusturuldu';
END $$;

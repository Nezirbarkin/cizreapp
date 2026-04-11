-- ============================================================================
-- ACIL DUZELTME: Mesaj gonderilemiyor - notifications INSERT hatasi
-- ============================================================================
-- Hata: column "message" of relation "notifications" does not exist
-- Cozum: Notifications tablosuna INSERT yapmadan sadece conversation guncelle

-- 1. Unique index problemi coz
DROP INDEX IF EXISTS conversations_unique_pair;

CREATE UNIQUE INDEX IF NOT EXISTS conversations_user_other_unique
ON conversations(user_id, other_user_id);

-- 2. Trigger fonksiyonu - SADECE conversation guncelleme, notifications INSERT yok
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
    
    -- NOT: Notifications INSERT'i kaldırıldı (başka bir trigger hallediyor)
    -- NOT: Push notification kaldırıldı (başka bir trigger hallediyor)
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 3. Trigger yeniden olustur
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- 4. Sonuc
DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'DUZELTME TAMAMLANDI';
    RAISE NOTICE '1. conversations_unique_pair index kaldirildi';
    RAISE NOTICE '2. conversations_user_other_unique index eklendi';
    RAISE NOTICE '3. Fonksiyon guncellendi (SADECE conversation guncelleme)';
    RAISE NOTICE '4. Notifications INSERT kaldirildi (ayri trigger var)';
    RAISE NOTICE '5. Mesaj gonderimi calismali';
    RAISE NOTICE '============================================================================';
END $$;

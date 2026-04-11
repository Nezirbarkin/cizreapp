-- ============================================================================
-- TAM DÜZELTME: Mesaj gönderilemiyor sorunu
-- ============================================================================
-- 1. Trigger: notifications INSERT kaldır (sütun adı yanlış)
-- 2. Trigger: Sadece conversation güncelle
-- 3. RPC: send_message_direct güncelle (notifications yok)

-- 1. TRIGGER DÜZELTME - notifications INSERT kaldır
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP TRIGGER IF EXISTS on_new_message_notify ON messages;

-- 2. Unique index problemi çöz
DROP INDEX IF EXISTS conversations_unique_pair;

CREATE UNIQUE INDEX IF NOT EXISTS conversations_user_other_unique
ON conversations(user_id, other_user_id);

-- 3. Basit trigger - SADECE conversation guncelleme
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
    
    -- NOT: Notifications INSERT KALDIRILDI (ayri trigger var)
    -- NOT: Push notification KALDIRILDI (ayri trigger var)
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 4. Trigger olustur
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- 5. RPC fonksiyonunu guncelle (notifications INSERT yok)
DROP FUNCTION IF EXISTS public.send_message_direct(UUID, TEXT);
DROP FUNCTION IF EXISTS public.send_message_direct(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.send_message_direct(
    p_conversation_id UUID,
    p_content TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
    v_created_at TIMESTAMPTZ;
    v_updated_at TIMESTAMPTZ;
    v_current_user UUID := auth.uid();
BEGIN
    IF v_current_user IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;
    
    INSERT INTO messages (
        conversation_id,
        sender_id,
        content
    ) VALUES (
        p_conversation_id,
        v_current_user,
        p_content
    )
    RETURNING id, created_at, updated_at
    INTO v_id, v_created_at, v_updated_at;
    
    RETURN json_build_object(
        'id', v_id,
        'conversation_id', p_conversation_id,
        'sender_id', v_current_user,
        'content', p_content,
        'is_read', false,
        'created_at', v_created_at,
        'updated_at', v_updated_at
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_message_direct(UUID, TEXT) TO authenticated;

-- 6. Sonuc
DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'TAM DÜZELTME TAMAMLANDI';
    RAISE NOTICE '1. Trigger: notifications INSERT kaldirildi';
    RAISE NOTICE '2. Trigger: SADECE conversation guncelleme yapar';
    RAISE NOTICE '3. Unique index duzeltildi';
    RAISE NOTICE '4. RPC: send_message_direct guncellendi';
    RAISE NOTICE '5. Mesaj gonderimi calismali';
    RAISE NOTICE '============================================================================';
END $$;

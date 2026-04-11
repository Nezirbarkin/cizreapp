-- ============================================================================
-- FIX: ON CONFLICT ERROR for messages table
-- ============================================================================
-- Hata: "there is no unique or exclusion constraint matching the ON CONFLICT specification"
-- Çözüm: (user_id, other_user_id) için unique constraint ekle

-- 1. Mevcut unique index'in adını kontrol et ve gerekirse düzelt
-- conversations_unique_pair index'i LEAST/GREATEST kullanıyor ama ON CONFLICT (user_id, other_user_id) kullanıyor
-- Bu iki farklı şey!

-- 2. Doğrudan (user_id, other_user_id) için unique constraint ekle
DO $$
BEGIN
    -- Önce mevcut constraint'i kontrol et ve varsa sil
    IF EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'conversations_user_other_unique'
    ) THEN
        ALTER TABLE conversations DROP CONSTRAINT conversations_user_other_unique;
    END IF;
    
    -- Yeni unique constraint ekle
    ALTER TABLE conversations 
    ADD CONSTRAINT conversations_user_other_unique 
    UNIQUE (user_id, other_user_id);
    
    RAISE NOTICE '✅ conversations_user_other_unique constraint added';
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE '⚠️ conversations_user_other_unique already exists';
END $$;

-- 3. Trigger fonksiyonunu yeniden oluştur (garanti için)
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP FUNCTION IF EXISTS update_conversation_on_message();

CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    conv_other_user_id UUID;
    sender_id UUID := NEW.sender_id;
BEGIN
    -- Konuşmanın other_user_id'sini al
    SELECT other_user_id INTO conv_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;

    -- Gönderen tarafın conversation'ını güncelle
    UPDATE conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW()
    WHERE user_id = sender_id 
      AND other_user_id = conv_other_user_id;

    -- Alıcı tarafın conversation'ını güncelle (ON CONFLICT artık çalışacak)
    INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count)
    VALUES (conv_other_user_id, sender_id, NEW.content, NEW.created_at, 1)
    ON CONFLICT (user_id, other_user_id) 
    DO UPDATE SET
        last_message = EXCLUDED.last_message,
        last_message_time = EXCLUDED.last_message_time,
        unread_count = conversations.unread_count + 1,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- 4. send_message_direct RPC fonksiyonunu da güncelle (güvenli versiyon)
DROP FUNCTION IF EXISTS public.send_message_direct(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.send_message_direct(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.send_message_direct(
    p_conversation_id TEXT,
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
    v_conv_id UUID;
BEGIN
    IF v_current_user IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;
    
    -- String'i UUID'ye cast et
    BEGIN
        v_conv_id := p_conversation_id::UUID;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid conversation_id: %', p_conversation_id;
    END;
    
    -- Mesajı ekle (trigger diğer tarafın conversation'ını otomatik oluşturacak)
    INSERT INTO messages (
        conversation_id,
        sender_id,
        content
    ) VALUES (
        v_conv_id,
        v_current_user,
        p_content
    )
    RETURNING id, created_at, updated_at
    INTO v_id, v_created_at, v_updated_at;
    
    -- JSON olarak döndür
    RETURN json_build_object(
        'id', v_id,
        'conversation_id', v_conv_id,
        'sender_id', v_current_user,
        'content', p_content,
        'is_read', false,
        'read_at', null,
        'created_at', v_created_at,
        'updated_at', v_updated_at
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_message_direct(TEXT, TEXT) TO authenticated;

-- 5. Kontrol sorgusu
SELECT
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'conversations'::regclass
AND contype = 'u';

-- 6. Onay mesajı
DO $$
BEGIN
    RAISE NOTICE '✅ FIX completed! ON CONFLICT error should be resolved.';
END $$;

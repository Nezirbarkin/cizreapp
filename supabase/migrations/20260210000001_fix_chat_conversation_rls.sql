-- ============================================================================
-- Chat Conversation RLS Fix - Trigger ve Policy Güncellemeleri
-- ============================================================================
-- Sorun: update_conversation_on_message() trigger fonksiyonu
-- alıcı için conversation oluştururken RLS policy'si tarafından engelleniyor.
-- Çözüm: Policy'yi SECURITY DEFINER fonksiyonları için güncelle

-- 1. Mevcut policy'i sil
DROP POLICY IF EXISTS "conversations_insert_own" ON conversations;

-- 2. Yeni policy: SECURITY DEFINER fonksiyonları için esneklik
CREATE POLICY "conversations_insert_own"
    ON conversations
    FOR INSERT
    TO authenticated
    WITH CHECK (
        -- Kullanıcı kendi konuşmasını oluşturabilir
        user_id = auth.uid()
        OR
        -- SECURITY DEFINER fonksiyonları (trigger) için:
        -- Eğer other_user_id auth.uid() ile eşleşiyorsa, bu o kullanıcının
        -- aldığı bir mesaj anlamına gelir (trigger tarafından oluşturuldu)
        other_user_id = auth.uid()
    );

-- 3. Trigger fonksiyonunu güncelle - SECURITY DEFINER ile
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_other_user_id UUID;
BEGIN
    -- Gönderenin konuşmasından diğer kullanıcıyı bul
    SELECT other_user_id INTO v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    -- Eğer other_user_id bulunamadıysa, işlemi durdur
    IF v_other_user_id IS NULL THEN
        RAISE WARNING 'Conversation not found for id: %', NEW.conversation_id;
        RETURN NEW;
    END IF;

    -- Gönderenin konuşmasını güncelle
    UPDATE conversations
    SET 
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;

    -- Alıcının konuşmasını oluştur veya güncelle
    -- NOT: user_id = alıcı, other_user_id = gönderen
    INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at)
    VALUES (v_other_user_id, NEW.sender_id, NEW.content, NEW.created_at, 1, NOW(), NOW())
    ON CONFLICT (user_id, other_user_id)
    DO UPDATE SET
        last_message = EXCLUDED.last_message,
        last_message_time = EXCLUDED.last_message_time,
        unread_count = conversations.unread_count + 1,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. UNIQUE constraint ekle - çift kaydı önlemek için
-- Önce mevcut varsa sil, sonra ekle
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'conversations_user_other_unique'
    ) THEN
        ALTER TABLE conversations DROP CONSTRAINT conversations_user_other_unique;
    END IF;
END $$;

ALTER TABLE conversations ADD CONSTRAINT conversations_user_other_unique
    UNIQUE (user_id, other_user_id);

-- 5. Onay
DO $$
BEGIN
    RAISE NOTICE 'Chat conversation RLS fix applied successfully!';
END $$;

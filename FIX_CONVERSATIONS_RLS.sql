-- ============================================================================
-- CHAT RLS POLICY DÜZELTMESI (Conversations + Messages)
-- ============================================================================
-- Sorun: "new row violates row-level security policy" (conversations ve messages)
-- Neden: Çakışan/eksik RLS policy'ler
-- Çözüm: Tüm chat policy'lerini temizle ve doğru olanları ekle
-- ============================================================================

-- 1. Tüm mevcut conversations policy'lerini temizle
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'conversations' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversations', pol.policyname);
        RAISE NOTICE 'Silindi: %', pol.policyname;
    END LOOP;
END $$;

-- 2. RLS'nin açık olduğundan emin ol
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- 3. SELECT policy - Kullanıcı kendi konuşmalarını görebilir
CREATE POLICY "conversations_select_own" ON public.conversations
    FOR SELECT TO authenticated
    USING (
        user_id = (select auth.uid())
        OR other_user_id = (select auth.uid())
    );

-- 4. INSERT policy - Kullanıcı konuşma oluşturabilir
CREATE POLICY "conversations_insert_own" ON public.conversations
    FOR INSERT TO authenticated
    WITH CHECK (
        user_id = (select auth.uid())
        OR other_user_id = (select auth.uid())
    );

-- 5. UPDATE policy - Kullanıcı kendi konuşmasını güncelleyebilir
CREATE POLICY "conversations_update_own" ON public.conversations
    FOR UPDATE TO authenticated
    USING (
        user_id = (select auth.uid())
        OR other_user_id = (select auth.uid())
    )
    WITH CHECK (
        user_id = (select auth.uid())
        OR other_user_id = (select auth.uid())
    );

-- 6. DELETE policy - Kullanıcı kendi konuşmasını silebilir
CREATE POLICY "conversations_delete_own" ON public.conversations
    FOR DELETE TO authenticated
    USING (
        user_id = (select auth.uid())
        OR other_user_id = (select auth.uid())
    );

-- 7. Trigger fonksiyonunu SECURITY DEFINER ile yeniden oluştur
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

-- ============================================================================
-- MESSAGES TABLOSU RLS POLICY'LERİ
-- ============================================================================

-- 8. Tüm mevcut messages policy'lerini temizle
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN
        SELECT policyname
        FROM pg_policies
        WHERE tablename = 'messages' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.messages', pol.policyname);
        RAISE NOTICE 'Silindi: %', pol.policyname;
    END LOOP;
END $$;

-- 9. RLS'nin açık olduğundan emin ol
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- 10. SELECT policy - Kullanıcı konuşmadaki mesajları görebilir
CREATE POLICY "messages_select_own" ON public.messages
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM conversations
            WHERE conversations.id = messages.conversation_id
            AND (conversations.user_id = (select auth.uid()) OR conversations.other_user_id = (select auth.uid()))
        )
    );

-- 11. INSERT policy - Kullanıcı mesaj gönderebilir
CREATE POLICY "messages_insert_own" ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (
        sender_id = (select auth.uid())
        AND EXISTS (
            SELECT 1 FROM conversations
            WHERE conversations.id = messages.conversation_id
            AND (conversations.user_id = (select auth.uid()) OR conversations.other_user_id = (select auth.uid()))
        )
    );

-- 12. UPDATE policy - Kullanıcı kendi mesajını güncelleyebilir
CREATE POLICY "messages_update_own" ON public.messages
    FOR UPDATE TO authenticated
    USING (
        sender_id = (select auth.uid())
    )
    WITH CHECK (
        sender_id = (select auth.uid())
    );

-- 13. DELETE policy - Kullanıcı kendi mesajını silebilir
CREATE POLICY "messages_delete_own" ON public.messages
    FOR DELETE TO authenticated
    USING (
        sender_id = (select auth.uid())
    );

-- 14. Doğrulama
DO $$
DECLARE
    v_conv_policy_count INTEGER;
    v_msg_policy_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_conv_policy_count
    FROM pg_policies
    WHERE tablename = 'conversations' AND schemaname = 'public';
    
    SELECT COUNT(*) INTO v_msg_policy_count
    FROM pg_policies
    WHERE tablename = 'messages' AND schemaname = 'public';
    
    RAISE NOTICE 'Toplam conversations policy sayisi: %', v_conv_policy_count;
    RAISE NOTICE 'Toplam messages policy sayisi: %', v_msg_policy_count;
    RAISE NOTICE 'Chat RLS duzeltmesi tamamlandi!';
END $$;

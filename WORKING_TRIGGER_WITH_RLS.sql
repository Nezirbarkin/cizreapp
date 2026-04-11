-- =====================================================
-- WORKING TRIGGER: Yeni mesajda conversation'ı güncelle
-- UUID cast sorunlarını önleyen FINAL versiyon
-- =====================================================

-- Tüm eski trigger'ları temizle
DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;
DROP FUNCTION IF EXISTS public.update_conversation_on_message() CASCADE;
DROP FUNCTION IF EXISTS public.update_updated_at_column() CASCADE;

-- ÇALIŞAN TRIGGER FONKSİYONU
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_other_user_id UUID;
    v_sender_id UUID;
    v_conv_id UUID;
BEGIN
    -- Değerleri al
    v_conv_id := NEW.conversation_id;
    v_sender_id := NEW.sender_id;
    
    -- Diğer kullanıcıyı bul
    SELECT other_user_id INTO v_other_user_id
    FROM conversations
    WHERE id = v_conv_id;
    
    IF v_other_user_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Gönderenin konuşmasını güncelle
    UPDATE conversations
    SET 
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW()
    WHERE id = v_conv_id;

    -- Alıcının konuşmasını oluştur veya güncelle
    INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at)
    VALUES (v_other_user_id, v_sender_id, NEW.content, NEW.created_at, 1, NOW(), NOW())
    ON CONFLICT (user_id, other_user_id)
    DO UPDATE SET
        last_message = EXCLUDED.last_message,
        last_message_time = EXCLUDED.last_message_time,
        unread_count = conversations.unread_count + 1,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı oluştur
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- updated_at trigger'ı
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER messages_updated_at
    BEFORE UPDATE ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- RLS'yi etkinleştir (gerçek güvenlik için)
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- ESKİ POLITİKALARI TEMİZLE
DROP POLICY IF EXISTS "conversations_delete_simple" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_simple" ON public.conversations;
DROP POLICY IF EXISTS "conversations_select_own" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_simple" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_own" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_own" ON public.conversations;
DROP POLICY IF EXISTS "conversations_delete_own" ON public.conversations;

CREATE POLICY "conversations_select_own"
ON public.conversations
FOR SELECT TO authenticated
USING (
    user_id = (select auth.uid()) OR other_user_id = (select auth.uid())
);

CREATE POLICY "conversations_insert_own"
ON public.conversations
FOR INSERT TO authenticated
WITH CHECK (
    user_id = (select auth.uid()) OR other_user_id = (select auth.uid())
);

CREATE POLICY "conversations_update_own"
ON public.conversations
FOR UPDATE TO authenticated
USING (
    user_id = (select auth.uid()) OR other_user_id = (select auth.uid())
)
WITH CHECK (
    user_id = (select auth.uid()) OR other_user_id = (select auth.uid())
);

CREATE POLICY "conversations_delete_own"
ON public.conversations
FOR DELETE TO authenticated
USING (
    user_id = (select auth.uid()) OR other_user_id = (select auth.uid())
);

-- Messages politikaları - TÜMKÜNÜ DROP ET
DROP POLICY IF EXISTS "messages_delete_simple" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_simple" ON public.messages;
DROP POLICY IF EXISTS "messages_select_simple" ON public.messages;
DROP POLICY IF EXISTS "messages_update_simple" ON public.messages;
DROP POLICY IF EXISTS "messages_select_own" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_own" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;

CREATE POLICY "messages_select_own"
ON public.messages
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = (select auth.uid()) OR c.other_user_id = (select auth.uid()))
    )
);

CREATE POLICY "messages_insert_own"
ON public.messages
FOR INSERT TO authenticated
WITH CHECK (
    sender_id = (select auth.uid())
    AND EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = (select auth.uid()) OR c.other_user_id = (select auth.uid()))
    )
);

CREATE POLICY "messages_update_own"
ON public.messages
FOR UPDATE TO authenticated
USING (
    sender_id = (select auth.uid())
)
WITH CHECK (
    sender_id = (select auth.uid())
);

CREATE POLICY "messages_delete_own"
ON public.messages
FOR DELETE TO authenticated
USING (
    sender_id = (select auth.uid())
);

DO $$
BEGIN
    RAISE NOTICE '✅ TRIGGER VE RLS ETKINLEŞTIRILDI!';
    RAISE NOTICE '  - Mesaj gönderince conversations güncellenecek';
    RAISE NOTICE '  - Sohbet kartlarında son mesaj görünecek';
END $$;

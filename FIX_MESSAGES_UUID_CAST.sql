-- =====================================================
-- Fix Messages UUID Type Casting Error
-- "operator does not exist: uuid = text" hatasını düzelt
-- =====================================================

-- Mevcut messages INSERT politikalarını temizle
DROP POLICY IF EXISTS "messages_insert_own" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_insert" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_auth" ON public.messages;

-- Mevcut messages SELECT politikalarını temizle
DROP POLICY IF EXISTS "messages_select_own" ON public.messages;
DROP POLICY IF EXISTS "messages_select_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_select" ON public.messages;

-- Mevcut messages UPDATE politikalarını temizle
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_update_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_update" ON public.messages;

-- Mevcut messages DELETE politikalarını temizle
DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;
DROP POLICY IF EXISTS "messages_delete_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_delete" ON public.messages;

-- =====================================================
-- Yeni RLS Politikaları (UUID cast ile düzeltildi)
-- =====================================================

-- INSERT Policy: Kullanıcı sadece kendi katıldığı conversation'lara mesaj gönderebilir
CREATE POLICY "messages_insert_own" 
ON public.messages 
FOR INSERT 
TO authenticated
WITH CHECK (
    -- sender_id kontrolü (UUID)
    sender_id = auth.uid() 
    AND 
    -- conversation_id kontrolü (UUID cast ile)
    EXISTS (
        SELECT 1 FROM public.conversations 
        WHERE conversations.id::text = messages.conversation_id::text
        AND (
            conversations.user_id = auth.uid() 
            OR 
            conversations.other_user_id = auth.uid()
        )
    )
);

-- SELECT Policy: Kullanıcı sadece kendi conversation'larındaki mesajları görebilir
CREATE POLICY "messages_select_own" 
ON public.messages 
FOR SELECT 
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.conversations 
        WHERE conversations.id::text = messages.conversation_id::text
        AND (
            conversations.user_id = auth.uid() 
            OR 
            conversations.other_user_id = auth.uid()
        )
    )
);

-- UPDATE Policy: Kullanıcı sadece kendi mesajlarını güncelleyebilir
CREATE POLICY "messages_update_own" 
ON public.messages 
FOR UPDATE 
TO authenticated
USING (
    sender_id = auth.uid()
)
WITH CHECK (
    sender_id = auth.uid()
);

-- DELETE Policy: Kullanıcı sadece kendi mesajlarını silebilir
CREATE POLICY "messages_delete_own" 
ON public.messages 
FOR DELETE 
TO authenticated
USING (
    sender_id = auth.uid()
);

-- =====================================================
-- Security check: RLS enabled mi?
-- =====================================================
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- Test ve Kontrol
-- =====================================================
DO $$
BEGIN
    RAISE NOTICE 'Messages RLS policies fixed with UUID casting!';
END $$;

-- Comment
COMMENT ON POLICY "messages_insert_own" ON public.messages IS 'Users can insert messages only in conversations they are part of';
COMMENT ON POLICY "messages_select_own" ON public.messages IS 'Users can only see messages from their own conversations';
COMMENT ON POLICY "messages_update_own" ON public.messages IS 'Users can only update their own messages';
COMMENT ON POLICY "messages_delete_own" ON public.messages IS 'Users can only delete their own messages';

-- =====================================================
-- Mevcut politikaları görüntüle (kontrol için)
-- =====================================================
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'messages'
ORDER BY policyname;

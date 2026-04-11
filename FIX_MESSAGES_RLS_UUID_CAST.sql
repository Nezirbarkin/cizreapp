-- =====================================================
-- FIX: Messages RLS Policies - UUID Cast Fix
-- UUID = text karşılaştırma hatasını düzeltir
-- =====================================================

-- Mevcut policy'leri kaldır
DROP POLICY IF EXISTS "messages_insert_own" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_authenticated" ON public.messages;
DROP POLICY IF EXISTS "messages_insert" ON public.messages;
DROP POLICY IF EXISTS "messages_select_own" ON public.messages;
DROP POLICY IF EXISTS "messages_select_authenticated" ON public.messages;
DROP POLICY IF EXISTS "messages_select" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;

-- INSERT Policy: Kullanıcı kendi katıldığı conversation'lara mesaj gönderebilir
-- conversation_id için açık UUID cast kullanıyoruz
CREATE POLICY "messages_insert_own"
ON public.messages
FOR INSERT TO authenticated
WITH CHECK (
    sender_id = auth.uid() 
    AND EXISTS (
        SELECT 1 
        FROM public.conversations 
        WHERE conversations.id::text = public.messages.conversation_id::text
        AND (conversations.user_id = auth.uid() OR conversations.other_user_id = auth.uid())
    )
);

-- SELECT Policy: Kullanıcı sadece kendi conversation'larındaki mesajları görebilir
CREATE POLICY "messages_select_own"
ON public.messages
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 
        FROM public.conversations 
        WHERE conversations.id::text = public.messages.conversation_id::text
        AND (conversations.user_id = auth.uid() OR conversations.other_user_id = auth.uid())
    )
);

-- UPDATE Policy: Kullanıcı sadece kendi mesajlarını güncelleyebilir
CREATE POLICY "messages_update_own"
ON public.messages
FOR UPDATE TO authenticated
USING (sender_id = auth.uid())
WITH CHECK (sender_id = auth.uid());

-- DELETE Policy: Kullanıcı sadece kendi mesajlarını silebilir
CREATE POLICY "messages_delete_own"
ON public.messages
FOR DELETE TO authenticated
USING (sender_id = auth.uid());

-- Başarı mesajı
DO $$
BEGIN
    RAISE NOTICE 'Messages RLS policies updated with UUID cast!';
END $$;

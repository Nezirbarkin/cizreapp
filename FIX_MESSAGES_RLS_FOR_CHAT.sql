-- ==============================================================================
-- FIX: Messages RLS - Sohbet İki Taraflı Çalışsın
-- ==============================================================================
-- Sorun: Her kullanıcı sadece kendi conversation_id'sindeki mesajları görüyor
-- Çözüm: Her iki kullanıcı arasındaki tüm conversation'lardaki mesajları görsün
-- ==============================================================================

-- Önce mevcut policy'leri kontrol et
SELECT 
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'messages'
ORDER BY policyname;

-- TÜM mevcut policy'leri kaldır
DROP POLICY IF EXISTS "messages_select_own" ON public.messages;
DROP POLICY IF EXISTS "messages_select_all" ON public.messages;
DROP POLICY IF EXISTS "messages_select_own_conversations" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_own" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "authenticated_can_select_messages" ON public.messages;
DROP POLICY IF EXISTS "users_can_view_own_messages" ON public.messages;
DROP POLICY IF EXISTS "messages_select_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_update_policy" ON public.messages;
DROP POLICY IF EXISTS "Users can view their own messages" ON public.messages;

-- Yeni policy: Authenticated kullanıcılar her iki tarafın mesajlarını görebilir
CREATE POLICY "messages_select_own_conversations"
ON public.messages
FOR SELECT
TO authenticated
USING (
    -- Mesajın ait olduğu conversation'ın kullanıcısı mıyım?
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
);

-- Insert policy - Kullanıcı kendi conversation'ına mesaj ekleyebilir
CREATE POLICY "messages_insert_own"
ON public.messages
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND c.user_id = auth.uid()
    )
);

-- Update policy - Sadece kendi mesajlarını güncelleyebilir (is_read için)
CREATE POLICY "messages_update_own"
ON public.messages
FOR UPDATE
TO authenticated
USING (sender_id = auth.uid())
WITH CHECK (sender_id = auth.uid());

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '✅ Messages RLS policy düzeltildi';
    RAISE NOTICE '✅ Her iki tarafın mesajları görünür';
    RAISE NOTICE '✅ Kullanıcılar kendi conversation''larına mesaj ekleyebilir';
END $$;

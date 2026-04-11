-- ==============================================================================
-- QUICK FIX: Messages RLS - Yeni İsimle Policy Oluştur
-- ==============================================================================

-- Önce tüm mevcut policy'leri kaldır
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'messages' AND schemaname = 'public'
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.messages';
        RAISE NOTICE 'Dropped policy: %', r.policyname;
    END LOOP;
END $$;

-- Yeni policy: Her iki tarafın mesajlarını görebilir
CREATE POLICY "messages_view_bidirectional"
ON public.messages
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = (SELECT auth.uid()) OR c.other_user_id = (SELECT auth.uid()))
    )
);

-- Insert policy
CREATE POLICY "messages_create_own"
ON public.messages
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND c.user_id = (SELECT auth.uid())
    )
);

-- Update policy
CREATE POLICY "messages_modify_own"
ON public.messages
FOR UPDATE
TO authenticated
USING (sender_id = (SELECT auth.uid()))
WITH CHECK (sender_id = (SELECT auth.uid()));

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE '✅ Messages RLS policy düzeltildi!';
    RAISE NOTICE '✅ Her iki tarafın mesajları görünür hale geldi';
    RAISE NOTICE '================================================================';
END $$;

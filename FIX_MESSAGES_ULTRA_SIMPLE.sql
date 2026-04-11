-- =====================================================
-- ULTRA SIMPLE FIX: Messages RLS - UUID Karşılaştırma olmadan
-- =====================================================

-- Mevcut politikaları temizle
DROP POLICY IF EXISTS "messages_insert_authenticated" ON public.messages;
DROP POLICY IF EXISTS "messages_select_own" ON public.messages;
DROP POLICY IF EXISTS "messages_select_authenticated" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_own" ON public.messages;

-- EN BASİT POLITİKALAR - Herhangi bir karşılaştırma yapmadan

-- INSERT: Sadece sender_id kontrolü
CREATE POLICY "messages_insert" 
ON public.messages 
FOR INSERT 
TO authenticated
WITH CHECK (sender_id = auth.uid());

-- SELECT: Herkes mesajları görsün (uygulama tarafında filtreleme yapılır)
CREATE POLICY "messages_select" 
ON public.messages 
FOR SELECT 
TO authenticated
USING (true);

-- UPDATE: Sadece kendi mesajı
CREATE POLICY "messages_update" 
ON public.messages 
FOR UPDATE 
TO authenticated
USING (sender_id = auth.uid())
WITH CHECK (sender_id = auth.uid());

-- DELETE: Sadece kendi mesajı
CREATE POLICY "messages_delete" 
ON public.messages 
FOR DELETE 
TO authenticated
USING (sender_id = auth.uid());

-- Kontrol
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'messages';

DO $$
BEGIN
    RAISE NOTICE 'Ultra simple RLS policies created!';
END $$;

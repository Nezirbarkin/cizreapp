-- =====================================================
-- COMPREHENSIVE FIX: Messages ve Conversations UUID Sync
-- Her iki tablonun id tiplerini eşleştirir
-- =====================================================

-- 1. Mevcut durum kontrolü
SELECT 'conversations.id' as table_column, 
       column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'conversations'
  AND column_name = 'id'

UNION ALL

SELECT 'messages.conversation_id',
       column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'messages'
  AND column_name = 'conversation_id';

-- 2. Tüm RLS politikalarını devre dışı bırak
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;

-- 3. Mevcut politikaları temizle
DROP POLICY IF EXISTS "messages_insert_authenticated" ON public.messages;
DROP POLICY IF EXISTS "messages_select_authenticated" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_own" ON public.messages;
DROP POLICY IF EXISTS "messages_select_own" ON public.messages;
DROP POLICY IF EXISTS "conversations_insert_authenticated" ON public.conversations;
DROP POLICY IF EXISTS "conversations_select_own" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_own" ON public.conversations;

-- 4. Her iki tablonun id tipini UUID'ye çevir
-- conversations tablosu için
ALTER TABLE public.conversations 
ALTER COLUMN id TYPE UUID USING id::UUID;

-- messages tablosu için
ALTER TABLE public.messages 
ALTER COLUMN conversation_id TYPE UUID USING conversation_id::UUID;

-- 5. RLS politikalarını yeniden oluştur (UUID ile doğru çalışır)
-- Messages policies
CREATE POLICY "messages_insert_authenticated" 
ON public.messages 
FOR INSERT 
TO authenticated
WITH CHECK (sender_id = auth.uid());

CREATE POLICY "messages_select_own" 
ON public.messages 
FOR SELECT 
TO authenticated
USING (
    sender_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
);

CREATE POLICY "messages_update_own" 
ON public.messages 
FOR UPDATE 
TO authenticated
USING (sender_id = auth.uid());

CREATE POLICY "messages_delete_own" 
ON public.messages 
FOR DELETE 
TO authenticated
USING (sender_id = auth.uid());

-- Conversations policies
CREATE POLICY "conversations_insert_authenticated" 
ON public.conversations 
FOR INSERT 
TO authenticated
WITH CHECK (
    user_id = auth.uid() OR other_user_id = auth.uid()
);

CREATE POLICY "conversations_select_own" 
ON public.conversations 
FOR SELECT 
TO authenticated
USING (
    user_id = auth.uid() OR other_user_id = auth.uid()
);

CREATE POLICY "conversations_update_own" 
ON public.conversations 
FOR UPDATE 
TO authenticated
USING (
    user_id = auth.uid() OR other_user_id = auth.uid()
);

-- 6. RLS'yi tekrar aktifleştir
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- 7. Sonuç kontrolü
SELECT 'FINAL - conversations.id' as table_column, 
       data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'conversations'
  AND column_name = 'id'

UNION ALL

SELECT 'FINAL - messages.conversation_id',
       data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'messages'
  AND column_name = 'conversation_id';

-- Politikaları listele
SELECT 'conversations policies' as table_name, policyname, cmd 
FROM pg_policies WHERE tablename = 'conversations'
UNION ALL
SELECT 'messages policies', policyname, cmd 
FROM pg_policies WHERE tablename = 'messages';

DO $$
BEGIN
    RAISE NOTICE 'UUID sync completed for conversations and messages!';
END $$;

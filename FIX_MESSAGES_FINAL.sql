-- =====================================================
-- FINAL FIX: Messages conversation_id Type Issue
-- Bu dosya conversation_id'yi tamamen UUID'ye çevirir
-- =====================================================

-- 1. RLS'yi geçici olarak kapat (schema değişikliği için)
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;

-- 2. Tüm RLS politikalarını kaldır
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'messages' 
        AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.messages', policy_record.policyname);
        RAISE NOTICE 'Dropped policy: %', policy_record.policyname;
    END LOOP;
END $$;

-- 3. Foreign key constraint'i kaldır
ALTER TABLE public.messages 
DROP CONSTRAINT IF EXISTS messages_conversation_id_fkey;

ALTER TABLE public.messages 
DROP CONSTRAINT IF EXISTS fk_messages_conversation;

-- 4. conversation_id kolonunu UUID'ye çevir
ALTER TABLE public.messages 
ALTER COLUMN conversation_id TYPE UUID USING conversation_id::UUID;

-- 5. Foreign key'i geri ekle
ALTER TABLE public.messages 
ADD CONSTRAINT messages_conversation_id_fkey 
FOREIGN KEY (conversation_id) 
REFERENCES public.conversations(id) 
ON DELETE CASCADE;

-- 6. RLS politikalarını yeniden oluştur (basit versiyon)
CREATE POLICY "messages_insert_authenticated" 
ON public.messages 
FOR INSERT 
TO authenticated
WITH CHECK (sender_id = auth.uid());

CREATE POLICY "messages_select_authenticated" 
ON public.messages 
FOR SELECT 
TO authenticated
USING (true);

CREATE POLICY "messages_update_own" 
ON public.messages 
FOR UPDATE 
TO authenticated
USING (sender_id = auth.uid())
WITH CHECK (sender_id = auth.uid());

CREATE POLICY "messages_delete_own" 
ON public.messages 
FOR DELETE 
TO authenticated
USING (sender_id = auth.uid());

-- 7. RLS'yi tekrar aç
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- 8. Sonuçları kontrol et
SELECT 
    column_name, 
    data_type, 
    udt_name
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'messages'
  AND column_name IN ('conversation_id', 'sender_id');

SELECT policyname, cmd FROM pg_policies WHERE tablename = 'messages';

-- 9. Başarı mesajı
DO $$
BEGIN
    RAISE NOTICE 'Messages table conversation_id fixed to UUID!';
END $$;

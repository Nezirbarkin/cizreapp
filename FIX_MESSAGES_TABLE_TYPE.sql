-- =====================================================
-- Fix Messages Table conversation_id Type Issue
-- UUID vs TEXT tip uyumsuzluğunu düzelt
-- =====================================================

-- 1. Önce mevcut messages tablosunun yapısını kontrol et
SELECT 
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'messages'
ORDER BY ordinal_position;

-- 2. conversations tablosundaki id kolonunun tipini kontrol et
SELECT 
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'conversations'
  AND column_name = 'id';

-- =====================================================
-- 3. Eğer conversation_id TEXT ise, UUID'ye çevir
-- =====================================================

DO $$ 
DECLARE
    conv_id_type text;
BEGIN
    -- messages.conversation_id tipini öğren
    SELECT data_type INTO conv_id_type
    FROM information_schema.columns
    WHERE table_schema = 'public' 
      AND table_name = 'messages'
      AND column_name = 'conversation_id';
    
    IF conv_id_type = 'text' OR conv_id_type = 'character varying' THEN
        RAISE NOTICE 'conversation_id TEXT tipinde, UUID''ye çevriliyor...';
        
        -- Foreign key constraint'i geçici olarak kaldır
        ALTER TABLE public.messages 
        DROP CONSTRAINT IF EXISTS messages_conversation_id_fkey;
        
        -- TEXT'i UUID'ye çevir
        ALTER TABLE public.messages 
        ALTER COLUMN conversation_id TYPE UUID USING conversation_id::UUID;
        
        -- Foreign key constraint'i geri ekle
        ALTER TABLE public.messages 
        ADD CONSTRAINT messages_conversation_id_fkey 
        FOREIGN KEY (conversation_id) 
        REFERENCES public.conversations(id) 
        ON DELETE CASCADE;
        
        RAISE NOTICE 'conversation_id başarıyla UUID tipine çevrildi!';
    ELSE
        RAISE NOTICE 'conversation_id zaten UUID tipinde: %', conv_id_type;
    END IF;
END $$;

-- =====================================================
-- 4. RLS Politikalarını yeniden oluştur (UUID ile)
-- =====================================================

-- Mevcut politikaları temizle
DROP POLICY IF EXISTS "messages_insert_own" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_insert" ON public.messages;
DROP POLICY IF EXISTS "messages_select_own" ON public.messages;
DROP POLICY IF EXISTS "messages_select_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_select" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_update_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;
DROP POLICY IF EXISTS "messages_delete_policy" ON public.messages;

-- INSERT Policy
CREATE POLICY "messages_insert_own" 
ON public.messages 
FOR INSERT 
TO authenticated
WITH CHECK (
    sender_id = auth.uid() 
    AND 
    EXISTS (
        SELECT 1 FROM public.conversations 
        WHERE conversations.id = messages.conversation_id
        AND (
            conversations.user_id = auth.uid() 
            OR 
            conversations.other_user_id = auth.uid()
        )
    )
);

-- SELECT Policy
CREATE POLICY "messages_select_own" 
ON public.messages 
FOR SELECT 
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.conversations 
        WHERE conversations.id = messages.conversation_id
        AND (
            conversations.user_id = auth.uid() 
            OR 
            conversations.other_user_id = auth.uid()
        )
    )
);

-- UPDATE Policy
CREATE POLICY "messages_update_own" 
ON public.messages 
FOR UPDATE 
TO authenticated
USING (sender_id = auth.uid())
WITH CHECK (sender_id = auth.uid());

-- DELETE Policy
CREATE POLICY "messages_delete_own" 
ON public.messages 
FOR DELETE 
TO authenticated
USING (sender_id = auth.uid());

-- RLS'yi etkinleştir
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- 5. Son kontrol: Tablo yapısını tekrar görüntüle
-- =====================================================
SELECT 
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'messages'
ORDER BY ordinal_position;

-- Politikaları kontrol et
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'messages'
ORDER BY policyname;

-- Başarı mesajı
DO $$
BEGIN
    RAISE NOTICE '✅ Messages tablosu UUID düzeltmesi ve RLS politikaları başarıyla güncellendi!';
END $$;

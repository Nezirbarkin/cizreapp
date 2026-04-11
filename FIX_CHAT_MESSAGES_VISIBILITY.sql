-- ==============================================================================
-- SOHBET MESAJLARI GÖRÜNME SORUNU FİX
-- ==============================================================================
-- Bu script, kullanıcıların karşı tarafın mesajlarını görmesini sağlar
-- Her iki kullanıcının da mesajları görebilmesi için RLS policy düzenlenir
-- ==============================================================================

-- ADIM 1: Mevcut durumu göster
SELECT 
    '=== MEVCUT MESSAGES POLICIES ===' as info;
    
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'messages';

-- ADIM 2: TÜM messages policy'lerini kaldır
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'messages' AND schemaname = 'public'
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.messages CASCADE';
        RAISE NOTICE 'Silindi: %', r.policyname;
    END LOOP;
END $$;

-- ADIM 3: YENİ POLICY - SELECT (Mesajları Görüntüleme)
-- Kullanıcı, kendisinin dahil olduğu HERHANGI bir conversation'daki mesajları görebilir
CREATE POLICY "messages_select_policy"
ON public.messages
FOR SELECT
TO authenticated
USING (
    -- Mesajın conversation_id'si, kullanıcının dahil olduğu herhangi bir conversation'a ait mi?
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
);

-- ADIM 4: YENİ POLICY - INSERT (Mesaj Gönderme)
-- Kullanıcı, sadece kendisinin user_id olarak sahibi olduğu conversation'a mesaj ekleyebilir
CREATE POLICY "messages_insert_policy"
ON public.messages
FOR INSERT
TO authenticated
WITH CHECK (
    -- Mesaj gönderen kişi, sender_id ile eşleşmeli
    sender_id = auth.uid()
    AND
    -- Ve bu conversation'ın user_id'si gönderen olmalı
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND c.user_id = auth.uid()
    )
);

-- ADIM 5: YENİ POLICY - UPDATE (Mesaj Güncelleme)
-- Kullanıcı, sadece kendi gönderdiği mesajları güncelleyebilir (örn: is_read)
CREATE POLICY "messages_update_policy"
ON public.messages
FOR UPDATE
TO authenticated
USING (
    -- Mesajın bulunduğu conversation'da kullanıcı dahil mi?
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
)
WITH CHECK (
    -- Güncelleme sonrası da aynı kontrolü yap
    EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
);

-- ADIM 6: YENİ POLICY - DELETE (Mesaj Silme)
-- Kullanıcı, sadece kendi gönderdiği mesajları silebilir
CREATE POLICY "messages_delete_policy"
ON public.messages
FOR DELETE
TO authenticated
USING (sender_id = auth.uid());

-- ADIM 7: RLS'nin açık olduğundan emin ol
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- ADIM 8: Conversations tablosu için de RLS kontrolü
SELECT 
    '=== CONVERSATIONS POLICIES ===' as info;
    
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'conversations';

-- ADIM 9: Eğer conversations policy'leri de problem çıkarıyorsa düzelt
-- Mevcut policy'leri kontrol et, gerekirse düzelt
DO $$
BEGIN
    -- Conversations için SELECT policy yoksa oluştur
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'conversations' 
        AND policyname = 'conversations_select_policy'
    ) THEN
        DROP POLICY IF EXISTS "Enable read access for own conversations" ON public.conversations;
        DROP POLICY IF EXISTS "conversations_select" ON public.conversations;
        
        CREATE POLICY "conversations_select_policy"
        ON public.conversations
        FOR SELECT
        TO authenticated
        USING (
            user_id = auth.uid() OR other_user_id = auth.uid()
        );
        
        RAISE NOTICE 'Conversations SELECT policy oluşturuldu';
    END IF;
END $$;

-- ADIM 10: Realtime için publication kontrol et
-- Realtime çalışması için messages tablosu publication'a ekli olmalı
DO $$
BEGIN
    -- supabase_realtime publication'ına messages ekle
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        -- Önce mevcut durumu kontrol et
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime' 
            AND tablename = 'messages'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
            RAISE NOTICE 'Messages tablosu realtime publication''a eklendi';
        ELSE
            RAISE NOTICE 'Messages zaten realtime publication''da';
        END IF;
    END IF;
END $$;

-- ADIM 11: Test sonuçları
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE '✅ MESSAGES RLS POLİCY GÜNCELLENDİ!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Yapılan Değişiklikler:';
    RAISE NOTICE '1. SELECT: Kullanıcı dahil olduğu tüm conversation''ların mesajlarını görebilir';
    RAISE NOTICE '2. INSERT: Kullanıcı sadece kendi conversation''ına mesaj ekleyebilir';
    RAISE NOTICE '3. UPDATE: Kullanıcı dahil olduğu conversation''ların mesajlarını güncelleyebilir';
    RAISE NOTICE '4. DELETE: Kullanıcı sadece kendi mesajlarını silebilir';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'ŞİMDİ UYGULAMAYI TEST EDİN!';
    RAISE NOTICE '================================================================';
END $$;

-- ADIM 12: Yeni policy durumunu göster
SELECT 
    '=== YENİ MESSAGES POLICIES ===' as info;
    
SELECT 
    policyname,
    cmd,
    SUBSTRING(qual::text, 1, 100) as policy_using,
    SUBSTRING(with_check::text, 1, 100) as policy_with_check
FROM pg_policies 
WHERE tablename = 'messages'
ORDER BY policyname;

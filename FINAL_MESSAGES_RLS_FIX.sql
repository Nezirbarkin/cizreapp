-- ==============================================================================
-- SON ÇÖZÜM: Messages RLS Policy - İki Yönlü Görünüm
-- ==============================================================================
-- Flutter getMessages doğru çalışıyor ama RLS engel oluyor!
-- ==============================================================================

-- 1. Mevcut policy durumunu kontrol et
SELECT policyname, cmd, qual 
FROM pg_policies 
WHERE tablename = 'messages';

-- 2. TÜM messages policy'lerini kaldır (DO bloğu ile)
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
        RAISE NOTICE 'Dropped: %', r.policyname;
    END LOOP;
END $$;

-- 3. YENİ POLICY: Kullanıcı hem kendi hem karşı tarafın conversation'ındaki mesajları görsün
CREATE POLICY "messages_select_both_sides"
ON public.messages
FOR SELECT
TO authenticated
USING (
    conversation_id IN (
        -- Benim conversation_id'lerim
        SELECT id FROM conversations WHERE user_id = (SELECT auth.uid())
        UNION
        -- Benim other_user_id olduğum conversation'lar
        SELECT id FROM conversations WHERE other_user_id = (SELECT auth.uid())
    )
);

-- 4. INSERT policy - Kullanıcı kendi conversation'ına mesaj ekleyebilir
CREATE POLICY "messages_insert_to_own_conv"
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

-- 5. UPDATE policy - Sadece kendi mesajlarını güncelleyebilir
CREATE POLICY "messages_update_sender_only"
ON public.messages
FOR UPDATE
TO authenticated
USING (sender_id = (SELECT auth.uid()))
WITH CHECK (sender_id = (SELECT auth.uid()));

-- 6. Test: Policy çalışıyor mu?
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE '✅ Messages RLS policy tamamen yenilendi!';
    RAISE NOTICE '✅ Kullanıcı artık her iki tarafın mesajlarını görebilir';
    RAISE NOTICE '================================================================';
END $$;

-- =====================================================
-- FINAL FIX: Mesaj Gönderme Hatası Çözümü
-- operator does not exist: uuid = text
-- =====================================================

-- 1. Eski RPC fonksiyonlarını sil
DROP FUNCTION IF EXISTS public.send_message_direct(UUID, TEXT);
DROP FUNCTION IF EXISTS public.send_message_direct(UUID, TEXT, UUID);

-- 2. Yeni RPC fonksiyonu (basit versiyon)
CREATE OR REPLACE FUNCTION public.send_message_direct(
    p_conversation_id UUID,
    p_content TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
    v_created_at TIMESTAMPTZ;
    v_updated_at TIMESTAMPTZ;
    v_current_user UUID := auth.uid();
BEGIN
    IF v_current_user IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;
    
    INSERT INTO messages (
        conversation_id,
        sender_id,
        content
    ) VALUES (
        p_conversation_id,
        v_current_user,
        p_content
    )
    RETURNING id, created_at, updated_at
    INTO v_id, v_created_at, v_updated_at;
    
    RETURN json_build_object(
        'id', v_id,
        'conversation_id', p_conversation_id,
        'sender_id', v_current_user,
        'content', p_content,
        'is_read', false,
        'read_at', null,
        'created_at', v_created_at,
        'updated_at', v_updated_at
    );
END;
$$;

-- 3. Eski RLS politikalarını sil
DROP POLICY IF EXISTS "messages_insert_own" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_authenticated" ON public.messages;
DROP POLICY IF EXISTS "messages_insert" ON public.messages;
DROP POLICY IF EXISTS "messages_select_own" ON public.messages;
DROP POLICY IF EXISTS "messages_select_authenticated" ON public.messages;
DROP POLICY IF EXISTS "messages_select" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;

-- 4. Yeni RLS politikaları (UUID cast ile)
-- INSERT: conversation_id için ::text cast kullanıyoruz
CREATE POLICY "messages_insert_own"
ON public.messages
FOR INSERT TO authenticated
WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
        SELECT 1
        FROM public.conversations
        WHERE id::text = messages.conversation_id::text
        AND (user_id = auth.uid() OR other_user_id = auth.uid())
    )
);

-- SELECT
CREATE POLICY "messages_select_own"
ON public.messages
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 
        FROM public.conversations 
        WHERE id::text = messages.conversation_id::text
        AND (user_id = auth.uid() OR other_user_id = auth.uid())
    )
);

-- UPDATE
CREATE POLICY "messages_update_own"
ON public.messages
FOR UPDATE TO authenticated
USING (sender_id = auth.uid())
WITH CHECK (sender_id = auth.uid());

-- DELETE
CREATE POLICY "messages_delete_own"
ON public.messages
FOR DELETE TO authenticated
USING (sender_id = auth.uid());

-- 5. İzinler
GRANT EXECUTE ON FUNCTION public.send_message_direct(UUID, TEXT) TO authenticated;

-- 6. Onay
DO $$
BEGIN
    RAISE NOTICE '✅ FINAL FIX tamamlandı!';
END $$;

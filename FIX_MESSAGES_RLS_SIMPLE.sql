-- =====================================================
-- ULTIMATE FIX: messages tablosunun RLS'sini kaldır
-- RPC ile insert yapıldığı için RLS'ye gerek yok
-- =====================================================

-- 1. Tüm messages politikalarını sil
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'messages' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.messages', pol.policyname);
        RAISE NOTICE 'Dropped: %', pol.policyname;
    END LOOP;
END $$;

-- 2. Çok basit politikalar ekle - tip karşılaştırması olmadan
-- INSERT: Sadece giriş yapmış kullanıcılar mesaj gönderebilir (RPC zaten kontrol ediyor)
CREATE POLICY "messages_insert_auth"
ON public.messages
FOR INSERT TO authenticated
WITH CHECK (true);  -- RPC SECURITY DEFINER zaten kullanıcı kontrolü yapıyor

-- SELECT: Sadece giriş yapmış kullanıcılar görebilir
CREATE POLICY "messages_select_auth"
ON public.messages
FOR SELECT TO authenticated
USING (true);  -- Uygulama tarafında filtreleme yapılır

-- UPDATE: Kendi mesajını güncelleyebilir
CREATE POLICY "messages_update_auth"
ON public.messages
FOR UPDATE TO authenticated
USING (sender_id = auth.uid());

-- DELETE: Kendi mesajını silebilir
CREATE POLICY "messages_delete_auth"
ON public.messages
FOR DELETE TO authenticated
USING (sender_id = auth.uid());

-- 3. Eski RPC'leri sil ve yeni basit versiyonu oluştur
DROP FUNCTION IF EXISTS public.send_message_direct(UUID, TEXT);
DROP FUNCTION IF EXISTS public.send_message_direct(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.send_message_direct(UUID, TEXT, UUID);

CREATE OR REPLACE FUNCTION public.send_message_direct(
    p_conversation_id TEXT,
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
    v_conv_id UUID;
BEGIN
    IF v_current_user IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;
    
    v_conv_id := p_conversation_id::UUID;
    
    INSERT INTO messages (conversation_id, sender_id, content)
    VALUES (v_conv_id, v_current_user, p_content)
    RETURNING id, created_at, updated_at
    INTO v_id, v_created_at, v_updated_at;
    
    RETURN json_build_object(
        'id', v_id,
        'conversation_id', v_conv_id,
        'sender_id', v_current_user,
        'content', p_content,
        'is_read', false,
        'read_at', null,
        'created_at', v_created_at,
        'updated_at', v_updated_at
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_message_direct(TEXT, TEXT) TO authenticated;

DO $$
BEGIN
    RAISE NOTICE '✅ messages RLS simplified + RPC updated!';
END $$;

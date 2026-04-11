-- =====================================================
-- TEST: RLS'yi tamamen kapat ve dene
-- Eğer bu çalışırsa, sorun kesinlikle RLS'dedir
-- =====================================================

-- RLS'yi kapat
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;

-- RPC'yi de basitleştir
DROP FUNCTION IF EXISTS public.send_message_direct(TEXT, TEXT);

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
    RAISE NOTICE '✅ RLS DISABLED - Test edin!';
END $$;

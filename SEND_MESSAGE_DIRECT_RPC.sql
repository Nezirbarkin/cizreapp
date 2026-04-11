-- =====================================================
-- RPC Function: send_message_direct  
-- Tüm tip sorunlarını çözen final versiyon
-- =====================================================

-- Önce mevcut fonksiyonları sil
DROP FUNCTION IF EXISTS public.send_message_direct(UUID, TEXT);
DROP FUNCTION IF EXISTS public.send_message_direct(UUID, TEXT, UUID);

-- Yeni basit versiyon - RETURNING sütun adı ile
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
    -- Kullanıcı kontrolü
    IF v_current_user IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;
    
    -- Mesajı ekle
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
    
    -- JSON olarak döndür
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

-- İzinler
GRANT EXECUTE ON FUNCTION public.send_message_direct(UUID, TEXT) TO authenticated;

DO $$
BEGIN
    RAISE NOTICE 'send_message_direct RPC function (final) created!';
END $$;

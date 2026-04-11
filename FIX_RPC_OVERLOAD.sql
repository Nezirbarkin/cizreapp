-- ==============================================================================
-- FIX: mark_sender_messages_read Function Overloading Hatası
-- ==============================================================================
-- Hata: Could not choose the best candidate function between:
-- public.mark_sender_messages_read(p_conversation_id => text, p_reader_id => uuid)
-- public.mark_sender_messages_read(p_conversation_id => uuid, p_reader_id => uuid)
-- Çözüm: Eski versiyonu sil ve yeni UUID versiyonunu tut
-- ==============================================================================

-- Fonksiyonu tamamen kaldır ve yeniden oluştur
DROP FUNCTION IF EXISTS public.mark_sender_messages_read(text, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.mark_sender_messages_read(uuid, uuid) CASCADE;

-- Yeni fonksiyon - sadece UUID versiyonu
CREATE OR REPLACE FUNCTION public.mark_sender_messages_read(
    p_conversation_id UUID,
    p_reader_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_other_user_id UUID;
    v_other_conv_id UUID;
BEGIN
    -- Konuşma bilgilerini al
    SELECT user_id, other_user_id INTO v_user_id, v_other_user_id
    FROM conversations
    WHERE id = p_conversation_id;
    
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;
    
    -- Karşı tarafın conversation_id'sini bul
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
    AND other_user_id = v_user_id;
    
    -- Her iki conversation'daki mesajları okundu yap
    -- (p_reader_id olmayan sender'ın mesajları)
    UPDATE messages
    SET is_read = true
    WHERE conversation_id IN (p_conversation_id, v_other_conv_id)
    AND sender_id != p_reader_id
    AND is_read = false;
    
    -- Okuyucunun unread_count'unu sıfırla
    UPDATE conversations
    SET unread_count = 0
    WHERE id = p_conversation_id;
END;
$$;

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '✅ mark_sender_messages_read fonksiyonu düzeltildi';
    RAISE NOTICE '✅ Function overloading hatası giderildi';
END $$;

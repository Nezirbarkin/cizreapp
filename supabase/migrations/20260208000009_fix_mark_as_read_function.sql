-- =============================================
-- Fix mark_messages_as_read function for two-way conversation system
-- =============================================
-- In the new two-way conversation system:
-- - User's conversation: user_id = currentUserId, other_user_id = otherUser
-- - Other's conversation: user_id = otherUser, other_user_id = currentUserId
-- When user reads messages, we need to update THEIR conversation (user_id = currentUserId)

-- Fonksiyonu düzelt
CREATE OR REPLACE FUNCTION mark_messages_as_read(p_conversation_id UUID)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
    v_other_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    
    -- Mesajları okundu olarak işaretle (kullanıcının aldığı mesajlar)
    UPDATE messages
    SET is_read = TRUE, updated_at = NOW()
    WHERE conversation_id = p_conversation_id
    AND sender_id != v_user_id
    AND is_read = FALSE;
    
    -- Kullanıcının kendi konuşmasındaki unread_count'u sıfırla
    -- NOT: İki yönlü sistemde kullanıcının konuşması user_id = currentUserId ile tutulur
    UPDATE conversations
    SET unread_count = 0, updated_at = NOW()
    WHERE id = p_conversation_id
    AND user_id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Fonksiyonun doğru çalıştığını test eden bir sorgu (opsiyonel)
-- SELECT mark_messages_as_read('conversation-uuid-here'::UUID);

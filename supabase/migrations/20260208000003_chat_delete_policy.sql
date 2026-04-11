-- ============================================================================
-- CHAT DELETE POLICY EKLEMESİ
-- ============================================================================
-- Sorun: conversations tablosunda DELETE policy yoktu, bu yüzden konuşmalar silinemiyordu.
-- Çözüm: Kullanıcının kendi konuşmalarını silebilmesi için DELETE policy eklendi.

-- 1. Conversations tablosu için DELETE policy
DROP POLICY IF EXISTS "conversations_delete_own" ON conversations;
CREATE POLICY "conversations_delete_own"
    ON conversations
    FOR DELETE
    TO authenticated
    USING (user_id = auth.uid() OR other_user_id = auth.uid());

-- 2. Messages tablosu için DELETE policy (opsiyonel - cascade ile zaten silinir)
DROP POLICY IF EXISTS "messages_delete_own" ON messages;
CREATE POLICY "messages_delete_own"
    ON messages
    FOR DELETE
    TO authenticated
    USING (
        sender_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM conversations
            WHERE conversations.id = messages.conversation_id
            AND (conversations.user_id = auth.uid() OR conversations.other_user_id = auth.uid())
        )
    );

COMMENT ON POLICY "conversations_delete_own" ON conversations IS 'Kullanıcılar kendi konuşmalarını silebilir';
COMMENT ON POLICY "messages_delete_own" ON messages IS 'Kullanıcılar kendi mesajlarını veya konuşmadaki mesajları silebilir';

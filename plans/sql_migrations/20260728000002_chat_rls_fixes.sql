-- =====================================================
-- DOSYA: supabase/migrations/20260728000002_chat_rls_fixes.sql
-- AMAÇ: Chat RLS + mailbox model + realtime filter
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. Conversations mailbox RLS kontrolü
DROP POLICY IF EXISTS "Users can view own conversations" ON conversations;
CREATE POLICY "Users can view own conversations" ON conversations
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR other_user_id = auth.uid());

-- 2. Messages RLS - sadece kendi conv'undaki mesajları görebilir
DROP POLICY IF EXISTS "Users can view messages in own conversations" ON messages;
CREATE POLICY "Users can view messages in own conversations" ON messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
  );

-- 3. Message INSERT - sadece kendi conv'una
DROP POLICY IF EXISTS "Users can insert messages to own conversations" ON messages;
CREATE POLICY "Users can insert messages to own conversations" ON messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND (c.user_id = auth.uid() OR c.other_user_id = auth.uid())
    )
  );

-- 4. mark_messages_as_read fonksiyonu - mailbox uyumlu
CREATE OR REPLACE FUNCTION mark_messages_as_read(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user UUID := auth.uid();
  v_other_user UUID;
  v_conv_owner UUID;
BEGIN
  IF v_current_user IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Conversation bilgilerini al
  SELECT user_id, other_user_id INTO v_conv_owner, v_other_user
  FROM conversations
  WHERE id = p_conversation_id;

  -- Sadece conversation sahibi okundu işaretleyebilir
  IF v_conv_owner != v_current_user THEN
    RETURN;
  END IF;

  -- Karşı tarafın mesajlarını okundu yap
  UPDATE messages
  SET is_read = TRUE, updated_at = NOW()
  WHERE conversation_id = p_conversation_id
    AND sender_id = v_other_user
    AND is_read = FALSE;

  -- Conversation unread_count sıfırla (sadece current user'ın conv'unda)
  UPDATE conversations
  SET unread_count = 0, updated_at = NOW()
  WHERE id = p_conversation_id
    AND user_id = v_current_user;
END;
$$;

REVOKE ALL ON FUNCTION mark_messages_as_read(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mark_messages_as_read(UUID) TO authenticated, service_role;

-- 5. Realtime publication ayarı (IF EXISTS olmadan)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'messages') THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE messages;
  END IF;
  ALTER PUBLICATION supabase_realtime ADD TABLE messages;

  IF EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'conversations') THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE conversations;
  END IF;
  ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
EXCEPTION WHEN OTHERS THEN
  -- Hata olursa yok say (zaten ekli olabilir)
  NULL;
END $$;

-- 6. Test query
-- SELECT mark_messages_as_read('00000000-0000-0000-0000-000000000000'::UUID);

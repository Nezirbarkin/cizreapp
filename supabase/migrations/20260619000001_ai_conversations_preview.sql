-- =====================================================
-- AI Konuşmalara son mesaj önizlemesi ekle
-- =====================================================

-- View oluştur (konuşmalar + son mesaj önizlemesi)
-- security_invoker ile alt tabloların RLS'ini kullanır
CREATE OR REPLACE VIEW public.ai_conversations_with_preview
  WITH (security_invoker=true)
AS
SELECT
  c.id,
  c.user_id,
  c.title,
  c.provider,
  c.message_count,
  c.last_message_at,
  c.is_archived,
  c.created_at,
  (
    SELECT LEFT(m.content, 100)
    FROM ai_messages m
    WHERE m.conversation_id = c.id AND m.role = 'assistant'
    ORDER BY m.created_at DESC
    LIMIT 1
  ) AS last_message_preview
FROM ai_conversations c;

-- =====================================================
-- ENABLE REALTIME for messages table
-- =====================================================

-- Add messages table to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;

-- Verify
SELECT 'Realtime enabled for messages' as status;

-- =====================================================
-- Fix Conversations updated_at Trigger
-- Mesaj geldiğinde conversation'ın updated_at'ini güncelle
-- =====================================================

-- Mevcut trigger'ı kaldır
DROP TRIGGER IF EXISTS update_conversation_on_new_message ON public.messages;
DROP FUNCTION IF EXISTS public.update_conversation_timestamp() CASCADE;

-- Yeni fonksiyon oluştur
CREATE OR REPLACE FUNCTION public.update_conversation_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Yeni mesaj eklendiğinde conversation'ın updated_at'ini güncelle
    UPDATE public.conversations
    SET updated_at = NEW.created_at
    WHERE id = NEW.conversation_id;
    
    RETURN NEW;
END;
$$;

-- Trigger oluştur - Her yeni mesajda conversation güncellensin
CREATE TRIGGER update_conversation_on_new_message
AFTER INSERT ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.update_conversation_timestamp();

-- Test için mesaj
DO $$
BEGIN
    RAISE NOTICE 'Conversation updated_at trigger created successfully!';
END $$;

COMMENT ON FUNCTION public.update_conversation_timestamp() IS 'Updates conversation updated_at when a new message is inserted';
COMMENT ON TRIGGER update_conversation_on_new_message ON public.messages IS 'Keeps conversation timestamp up to date';

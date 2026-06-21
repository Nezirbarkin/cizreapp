-- AI mesaj trigger hatasını düzelt - V3 (KAPSAMALI)
-- Tüm triggerları kontrol et ve sadece gerekli olanı koru

-- 1. ai_messages tablosundaki TÜM triggerları görüntüle
SELECT 
  trigger_name,
  action_order,
  event_manipulation,
  event_object_schema,
  event_object_catalog,
  action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'ai_messages'
AND event_object_schema = 'public';

-- 2. ai_messages tablosundaki TÜM triggerları sil
DROP TRIGGER IF EXISTS ai_message_insert_trigger ON public.ai_messages;
DROP TRIGGER IF EXISTS ai_messages_updated_at_trigger ON public.ai_messages;
DROP TRIGGER IF EXISTS update_updated_at_trigger ON public.ai_messages;
DROP TRIGGER IF EXISTS set_updated_at ON public.ai_messages;

-- 3. ai_on_message_insert fonksiyonunu yeniden oluştur
CREATE OR REPLACE FUNCTION public.ai_on_message_insert()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.ai_conversations
  SET
    message_count = COALESCE(message_count, 0) + 1,
    last_message_at = NOW()
  WHERE id = NEW.conversation_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Sadece bizim trigger'ımızı oluştur
CREATE TRIGGER ai_message_insert_trigger
  AFTER INSERT ON public.ai_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.ai_on_message_insert();

-- 5. Şimdi test INSERT yap
INSERT INTO ai_messages (conversation_id, user_id, role, content)
VALUES ('80c03746-b80b-4a83-9825-4b78a545db50', '78665f8b-6a07-40f3-b13d-d4b5a29296c6', 'user', 'Test mesajı V3');

-- 6. Sonuçları kontrol et
SELECT * FROM ai_messages ORDER BY created_at DESC LIMIT 5;

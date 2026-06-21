-- AI mesaj trigger hatasını düzelt
-- Sorun: ai_on_message_insert trigger fonksiyonu NEW.updated_at kullanıyor ama ai_messages tablosunda bu alan yok

-- 1. Mevcut trigger fonksiyonunu görüntüle
-- CREATE OR REPLACE FUNCTION ile düzelt

CREATE OR REPLACE FUNCTION public.ai_on_message_insert()
RETURNS TRIGGER AS $$
BEGIN
  -- Konuşma tablosunu güncelle
  UPDATE public.ai_conversations
  SET
    message_count = message_count + 1,
    last_message_at = NOW()
  WHERE id = NEW.conversation_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Trigger'ı yeniden oluştur (varsa silip yeniden oluştur)
DROP TRIGGER IF EXISTS ai_message_insert_trigger ON public.ai_messages;

CREATE TRIGGER ai_message_insert_trigger
  AFTER INSERT ON public.ai_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.ai_on_message_insert();

-- 3. Test INSERT
INSERT INTO ai_messages (conversation_id, user_id, role, content)
VALUES ('80c03746-b80b-4a83-9825-4b78a545db50', '78665f8b-6a07-40f3-b13d-d4b5a29296c6', 'user', 'Test mesajı 2');

-- 4. Sonuçları kontrol et
SELECT * FROM ai_messages ORDER BY created_at DESC LIMIT 5;

-- AI mesaj trigger hatasını düzelt - V2
-- Sorun: ai_on_message_insert trigger fonksiyonu update_updated_at_column() çağırıyor
-- Bu fonksiyon NEW.updated_at bekliyor ama ai_messages'te bu kolon yok

-- 1. Önce trigger'ı devre dışı bırak
DROP TRIGGER IF EXISTS ai_message_insert_trigger ON public.ai_messages;

-- 2. Mevcut fonksiyonu yeniden tanımla (update_updated_at_column çağrısını kaldır)
CREATE OR REPLACE FUNCTION public.ai_on_message_insert()
RETURNS TRIGGER AS $$
BEGIN
  -- Konuşma tablosunu güncelle (title güncelleme işlemi de var)
  UPDATE public.ai_conversations
  SET
    message_count = message_count + 1,
    last_message_at = NOW()
  WHERE id = NEW.conversation_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Trigger'ı yeniden oluştur
CREATE TRIGGER ai_message_insert_trigger
  AFTER INSERT ON public.ai_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.ai_on_message_insert();

-- 4. Şimdi test INSERT yap
INSERT INTO ai_messages (conversation_id, user_id, role, content)
VALUES ('80c03746-b80b-4a83-9825-4b78a545db50', '78665f8b-6a07-40f3-b13d-d4b5a29296c6', 'user', 'Test mesajı 3');

-- 5. Sonuçları kontrol et
SELECT * FROM ai_messages ORDER BY created_at DESC LIMIT 5;

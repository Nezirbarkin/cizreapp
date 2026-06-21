-- AI mesaj trigger hatasını düzelt - V4
-- Sorun: ai_conversations tablosunda update_updated_at_column() trigger'ı var
-- O trigger NEW.updated_at bekliyor ama ai_conversations'ta bu kolon farklı olabilir

-- 1. TÜM triggerları kontrol et
SELECT 
  event_object_table as table_name,
  trigger_name,
  action_statement
FROM information_schema.triggers 
WHERE event_object_schema = 'public'
AND event_object_table IN ('ai_messages', 'ai_conversations');

-- 2. ai_conversations tablosundaki tüm triggerları sil
DROP TRIGGER IF EXISTS ai_messages_updated_at_trigger ON public.ai_conversations;
DROP TRIGGER IF EXISTS update_updated_at_trigger ON public.ai_conversations;
DROP TRIGGER IF EXISTS set_updated_at ON public.ai_conversations;
DROP TRIGGER IF EXISTS ai_conversations_updated_at ON public.ai_conversations;

-- 3. ai_conversations tablosu için update_updated_at_column fonksiyonunu güncelle
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
EXCEPTION WHEN undefined_column THEN
    -- updated_at kolonu yoksa hata verme, devam et
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. ai_conversations için basit bir updated_at trigger'ı ekle
ALTER TABLE public.ai_conversations 
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

CREATE OR REPLACE TRIGGER ai_conversations_updated_at
    BEFORE UPDATE ON public.ai_conversations
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- 5. Şimdi test INSERT yap
INSERT INTO ai_messages (conversation_id, user_id, role, content)
VALUES ('80c03746-b80b-4a83-9825-4b78a545db50', '78665f8b-6a07-40f3-b13d-d4b5a29296c6', 'user', 'Test mesajı V4');

-- 6. Sonuçları kontrol et
SELECT * FROM ai_messages ORDER BY created_at DESC LIMIT 5;

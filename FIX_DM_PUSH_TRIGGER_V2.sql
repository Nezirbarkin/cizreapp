-- ============================================================================
-- 1:1 SOHBET PUSH BİLDİRİM TRİGGER - V2 (DOĞRU ALICI BULMA)
-- ============================================================================
-- conversations tablosu: her kullanıcı için 1 satır
-- sender'ın conversation_id → user_id=sender, other_user_id=alıcı
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_direct_message()
RETURNS TRIGGER AS $$
DECLARE
  recipient_id UUID;
  sender_name TEXT;
  function_url TEXT;
  anon_key TEXT;
  request_id BIGINT;
BEGIN
  -- sender'ın conversation satırından other_user_id = alıcı
  SELECT other_user_id INTO recipient_id
  FROM conversations
  WHERE id = NEW.conversation_id
  AND user_id = NEW.sender_id
  LIMIT 1;

  -- Bulunamazsa, tersinden dene
  IF recipient_id IS NULL THEN
    SELECT user_id INTO recipient_id
    FROM conversations
    WHERE id = NEW.conversation_id
    AND other_user_id = NEW.sender_id
    LIMIT 1;
  END IF;

  IF recipient_id IS NULL THEN
    RAISE LOG 'DM push: recipient not found for conv=% sender=%', NEW.conversation_id, NEW.sender_id;
    RETURN NEW;
  END IF;

  -- Gönderen adını al
  SELECT COALESCE(full_name, username, 'Biri') INTO sender_name
  FROM profiles
  WHERE id = NEW.sender_id;

  -- Push gönder
  function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
  anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';

  BEGIN
    SELECT net.http_post(
      function_url,
      jsonb_build_object(
        'user_id', recipient_id::text,
        'title', sender_name,
        'body', LEFT(NEW.content, 100),
        'data', jsonb_build_object(
          'type', 'chat',
          'conversation_id', NEW.conversation_id::text,
          'message_id', NEW.id::text
        )
      ),
      '{}'::jsonb,
      jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || anon_key
      ),
      5000
    ) INTO request_id;

    RAISE LOG 'DM push sent: request_id=% to=% from=%', request_id, recipient_id, NEW.sender_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'DM push failed: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger'ı oluştur
DROP TRIGGER IF EXISTS notify_direct_message_trigger ON messages;
CREATE TRIGGER notify_direct_message_trigger
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_direct_message();

-- Kontrol
SELECT '✅ 1:1 sohbet push trigger oluşturuldu (v2)!' AS durum;
SELECT event_object_table, trigger_name, event_manipulation
FROM information_schema.triggers
WHERE trigger_name = 'notify_direct_message_trigger';

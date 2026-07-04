-- ============================================================================
-- MIGRATION: 20260703_DM_PUSH_TRIGGER.sql
-- -----------------------------------------------------------------------------
-- AMAC: Birebir (1:1) sohbette alıcıya PUSH bildirimi gönder.
--
-- ALTYAPI (hazır ve çalışıyor): messages INSERT trigger → net.http_post (pg_net)
--   → Edge Function send-push-notification → FCM v1 (profiles.fcm_token).
--   Grup mesajı push'u (notify_group_message) aynı deseni kullanıyor.
--
-- MAILBOX MODELI + ÇİFT PUSH SORUNU:
--   send_message_with_recipient RPC her mantıksal mesaj için İKİ messages satırı
--   ekler (gönderenin conv'u + alıcının conv'u). Eski notify_direct_message (V2)
--   her iki satırda da alıcıyı bulup push atıyordu → alıcı 2 push alıyordu.
--   ÇÖZÜM: Push YALNIZCA GÖNDERENİN kopyasında (conversations.user_id = sender)
--   üretilir; alıcının kopyası atlanır. Böylece tam olarak 1 push gider.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.notify_direct_message()
RETURNS TRIGGER AS $$
DECLARE
  recipient_id UUID;
  sender_name TEXT;
  function_url TEXT;
  anon_key TEXT;
  request_id BIGINT;
BEGIN
  -- Yalnızca GÖNDERENİN conversation kopyasını işle (çift push önleme):
  -- bu satırda conversations.user_id = NEW.sender_id olur ve other_user_id = alıcı.
  -- Alıcının kopyasında (user_id = alıcı) bu sorgu NULL döner → push atlanır.
  SELECT other_user_id INTO recipient_id
  FROM conversations
  WHERE id = NEW.conversation_id
    AND user_id = NEW.sender_id
  LIMIT 1;

  IF recipient_id IS NULL THEN
    -- Alıcının mailbox kopyası veya bilinmeyen conv → bir şey yapma.
    RETURN NEW;
  END IF;

  -- Gönderen adı
  SELECT COALESCE(full_name, username, 'Biri') INTO sender_name
  FROM profiles
  WHERE id = NEW.sender_id;

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
          'message_id', NEW.id::text,
          'sender_id', NEW.sender_id::text
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

DROP TRIGGER IF EXISTS notify_direct_message_trigger ON public.messages;
CREATE TRIGGER notify_direct_message_trigger
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_direct_message();

-- Doğrulama
SELECT trigger_name, event_object_table, event_manipulation
FROM information_schema.triggers
WHERE trigger_name = 'notify_direct_message_trigger';

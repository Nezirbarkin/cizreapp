-- ============================================================================
-- 1) GRUP SOHBET SESSİZ DÜZELTMESİ + 2) DİREKT MESAJ PUSH TRİGGER
-- ============================================================================

-- ============================================================================
-- 1. GRUP SOHBET TRİGGER DÜZELTMESİ - is_muted NULL ve true kontrolü
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_group_message()
RETURNS TRIGGER AS $$
DECLARE
  member RECORD;
  sender_name TEXT;
  group_name TEXT;
  function_url TEXT;
  anon_key TEXT;
  request_id BIGINT;
BEGIN
  -- Gönderenin adını al
  SELECT COALESCE(full_name, username, 'Biri') INTO sender_name
  FROM profiles
  WHERE id = NEW.sender_id;

  -- Grup adını al
  SELECT name INTO group_name
  FROM groups
  WHERE id = NEW.group_id;

  -- Edge Function URL ve key
  function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
  anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';

  -- Tüm grup üyeleri için (gönderen hariç)
  FOR member IN
    SELECT user_id, COALESCE(is_muted, false) AS is_muted
    FROM group_members
    WHERE group_id = NEW.group_id
    AND user_id != NEW.sender_id
  LOOP
    -- unread_count artır (her üye için, sessiz olsa bile)
    UPDATE group_members
    SET unread_count = unread_count + 1
    WHERE group_id = NEW.group_id
    AND user_id = member.user_id;

    -- SADECE SESSİZ OLMAYAN üyelere push gönder
    IF member.is_muted = false THEN
      BEGIN
        SELECT net.http_post(
          function_url,
          jsonb_build_object(
            'user_id', member.user_id::text,
            'title', group_name,
            'body', sender_name || ': ' || LEFT(NEW.content, 100),
            'data', jsonb_build_object(
              'type', 'group_message',
              'group_id', NEW.group_id,
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
      EXCEPTION WHEN OTHERS THEN
        RAISE LOG 'Group push failed for user=%: %', member.user_id, SQLERRM;
      END;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS notify_group_message_trigger ON group_messages;
CREATE TRIGGER notify_group_message_trigger
  AFTER INSERT ON group_messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_group_message();

-- ============================================================================
-- 2. DİREKT MESAJ (1:1) PUSH TRİGGER
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
  -- conversations tablosundan alıcıyı bul
  SELECT other_user_id INTO recipient_id
  FROM conversations
  WHERE id = NEW.conversation_id
  AND user_id != NEW.sender_id
  LIMIT 1;

  -- Eğer bulunamazsa, conversation'ı tersinden bul
  IF recipient_id IS NULL THEN
    SELECT user_id INTO recipient_id
    FROM conversations
    WHERE id = NEW.conversation_id
    AND user_id != NEW.sender_id
    LIMIT 1;
  END IF;

  IF recipient_id IS NULL THEN
    RAISE LOG 'Direct message: recipient not found for conversation=%', NEW.conversation_id;
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

    RAISE LOG 'Direct message push sent: request_id=% to=%', request_id, recipient_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'Direct message push failed: %', SQLERRM;
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

-- ============================================================================
-- KONTROL
-- ============================================================================
SELECT '✅ Grup sessiz + Direkt mesaj push trigger oluşturuldu!' AS durum;

SELECT event_object_table, trigger_name, event_manipulation
FROM information_schema.triggers
WHERE trigger_name IN ('notify_group_message_trigger', 'notify_direct_message_trigger');

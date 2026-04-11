-- ============================================================================
-- GRUP SOHBET PUSH BİLDİRİM TRİGGER'I
-- ============================================================================
-- Yeni grup mesajı geldiğinde:
-- 1. Gönderen hariç tüm üyelerin unread_count'unu artır
-- 2. Sessiz olmayan üyelere push bildirim gönder
-- ============================================================================

-- 1. Grup mesajı geldiğinde unread_count artır ve push gönder
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
    SELECT user_id, is_muted
    FROM group_members
    WHERE group_id = NEW.group_id
    AND user_id != NEW.sender_id
  LOOP
    -- unread_count artır (her üye için)
    UPDATE group_members
    SET unread_count = unread_count + 1
    WHERE group_id = NEW.group_id
    AND user_id = member.user_id;

    -- Sessiz değilse push gönder
    IF member.is_muted = false OR member.is_muted IS NULL THEN
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

-- 2. Trigger oluştur
DROP TRIGGER IF EXISTS notify_group_message_trigger ON group_messages;
CREATE TRIGGER notify_group_message_trigger
  AFTER INSERT ON group_messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_group_message();

-- 3. Kontrol
SELECT '✅ Grup sohbet push trigger oluşturuldu!' AS durum;
SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE event_object_table = 'group_messages';

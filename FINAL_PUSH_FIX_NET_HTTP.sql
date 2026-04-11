-- ============================================================================
-- PUSH NOTIFICATION TRIGGER - SON DÜZELTME (NET.HTTP_POST)
-- ============================================================================
-- extensions.http_post yerine net.http_post kullan!
-- ============================================================================

-- Push notification gönderen fonksiyon (DOĞRU VERSİYON)
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER AS $$
DECLARE
  function_url TEXT;
  anon_key TEXT;
  request_id BIGINT;
BEGIN
  -- message ve chat tipleri için push gönderme (ayrı chat sistemi var)
  IF NEW.type IN ('message', 'chat') THEN
    RAISE LOG 'Push skipped for chat type: %', NEW.type;
    RETURN NEW;
  END IF;
  
  -- Supabase Edge Function URL
  function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
  
  -- Supabase anon key
  anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';
  
  -- Edge Function'ı çağır (async) - net.http_post kullan!
  BEGIN
    SELECT net.http_post(
      function_url,
      jsonb_build_object(
        'user_id', NEW.user_id::text,
        'title', COALESCE(NEW.title, 'Yeni Bildirim'),
        'body', COALESCE(NEW.content, ''),
        'data', jsonb_build_object(
          'notification_id', NEW.id,
          'type', NEW.type,
          'actor_id', COALESCE(NEW.actor_id::text, ''),
          'entity_id', COALESCE(NEW.entity_id, '')
        )
      ),
      '{}'::jsonb,
      jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || anon_key
      ),
      5000
    ) INTO request_id;
    
    RAISE LOG 'Push notification request sent: request_id=% type=% user=%', request_id, NEW.type, NEW.user_id;
    
  EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'Push notification failed: %', SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;
CREATE TRIGGER notifications_push_trigger
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION send_push_on_notification();

SELECT '✅ Push notification trigger güncellendi (net.http_post)!' AS durum;

-- Test: 09d4668c kullanıcısına bildirim oluştur
INSERT INTO notifications (user_id, type, title, content, is_read, created_at)
VALUES (
  '09d4668c-639e-417c-9304-fdd0ce5a045d',
  'post_like',
  'TEST PUSH BİLDİRİMİ',
  'Bu push bildirim olarak gelmeli!',
  false,
  NOW()
) RETURNING id, title, created_at;

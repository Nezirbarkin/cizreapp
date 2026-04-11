-- ============================================================================
-- PUSH NOTIFICATION TRIGGER - DÜZELTİLMİŞ VERSİYON
-- ============================================================================
-- extensions.http_post doğru parametre sırası ile çağrılıyor
-- request_id döndürdüğü için SELECT * INTO yerine sadece çağrı yapıyoruz
-- ============================================================================

-- Push notification gönderen fonksiyon (DÜZELTİLMİŞ)
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
  
  -- Edge Function'ı çağır (async)
  -- Parametre sırası: url, body, params, headers, timeout_milliseconds
  BEGIN
    SELECT extensions.http_post(
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
      '{}'::jsonb,  -- params (boş)
      jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || anon_key
      ),
      5000  -- timeout
    ) INTO request_id;
    
    -- Log tut (hata ayıklama için)
    RAISE LOG 'Push notification request sent: request_id=% type=% user=%', request_id, NEW.type, NEW.user_id;
    
  EXCEPTION WHEN OTHERS THEN
    -- Hata olursa log tut ama trigger'ı engelleme
    RAISE LOG 'Push notification failed: %', SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;
CREATE TRIGGER notifications_push_trigger
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION send_push_on_notification();

-- Kontrol et
SELECT 'Push notification trigger güncellendi!' AS durum;
SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE event_object_table = 'notifications'
AND trigger_name = 'notifications_push_trigger';

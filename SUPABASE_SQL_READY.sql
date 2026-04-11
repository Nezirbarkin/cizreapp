-- ============================================================================
-- PUSH NOTIFICATION DATABASE TRIGGER - DÜZELTILMIŞ VERSİYON
-- ============================================================================

-- HTTP extension'ı yükle (Edge Function çağırmak için)
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;

-- Push notification gönderen fonksiyon
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER AS $$
DECLARE
  user_fcm_token TEXT;
  function_url TEXT;
  anon_key TEXT;
  http_response extensions.http_request;
BEGIN
  -- Kullanıcının FCM token'ını al
  SELECT fcm_token INTO user_fcm_token
  FROM profiles
  WHERE id = NEW.user_id;
  
  -- FCM token yoksa çık (async olarak engellememek için)
  IF user_fcm_token IS NULL OR user_fcm_token = '' THEN
    RETURN NEW;
  END IF;
  
  -- Supabase Edge Function URL
  function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
  
  -- Supabase anon key
  anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';
  
  -- Edge Function'ı çağır (async, timeout 5 saniye)
  BEGIN
    SELECT * INTO http_response
    FROM extensions.http_post(
      url := function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || anon_key
      ),
      body := jsonb_build_object(
        'fcm_token', user_fcm_token,
        'title', COALESCE(NEW.title, 'Yeni Bildirim'),
        'body', COALESCE(NEW.content, ''),
        'data', jsonb_build_object(
          'notification_id', NEW.id,
          'type', NEW.type
        )
      ),
      timeout_milliseconds := 5000
    );
    
    -- Log tut (hata ayıklama için)
    RAISE LOG 'Push notification sent: %', http_response;
    
  EXCEPTION WHEN OTHERS THEN
    -- Hata olursa log tut ama trigger'ı engelleme
    RAISE LOG 'Push notification failed: %', SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger oluştur (yenisi varsa önce sil)
DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;
CREATE TRIGGER notifications_push_trigger
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION send_push_on_notification();

-- Trigger oluşturuldu
SELECT 'Trigger başarıyla kuruldu!' as sonuc;

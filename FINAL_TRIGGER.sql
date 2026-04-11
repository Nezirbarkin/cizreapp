-- ============================================================================
-- PUSH NOTIFICATION TRIGGER - TAMAMEN YENİDEN (WORKING VERSION)
-- ============================================================================

-- HTTP extension'ı kur
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;

-- Eski trigger ve fonksiyonu sil
DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;
DROP FUNCTION IF EXISTS send_push_on_notification();

-- Yeni push notification fonksiyonu
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_fcm_token TEXT;
  function_url TEXT;
  anon_key TEXT;
BEGIN
  -- FCM token al
  SELECT fcm_token INTO user_fcm_token
  FROM profiles
  WHERE id = NEW.user_id;
  
  -- FCM token yoksa çık
  IF user_fcm_token IS NULL OR user_fcm_token = '' THEN
    RAISE LOG 'FCM token yok, push notification gönderilmiyor';
    RETURN NEW;
  END IF;
  
  -- Edge Function URL
  function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
  
  -- Anon key
  anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';
  
  -- Edge Function çağır
  PERFORM extensions.http((
    'POST',
    function_url,
    ARRAY[
      extensions.http_header('Content-Type', 'application/json'),
      extensions.http_header('Authorization', 'Bearer ' || anon_key)
    ],
    'application/json',
    json_build_object(
      'fcm_token', user_fcm_token,
      'title', COALESCE(NEW.title, 'Yeni Bildirim'),
      'body', COALESCE(NEW.content, ''),
      'data', json_build_object(
        'notification_id', NEW.id::text,
        'type', NEW.type::text
      )
    )::text
  )::extensions.http_request);
  
  RAISE LOG 'Push notification Edge Function çağrıldı';
  
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'Push notification hatası: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- Trigger oluştur
CREATE TRIGGER notifications_push_trigger
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION send_push_on_notification();

-- Başarı mesajı
SELECT 'Trigger başarıyla kuruldu! Test etmek için bildirim ekle.' AS sonuc;

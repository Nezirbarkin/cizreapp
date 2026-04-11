-- ============================================================================
-- FIX: Verification Code Push Notification
-- ============================================================================
-- Sorun: Sipariş onay kodu push olarak gelmiyor
-- Çözüm: Trigger ve Edge Function arasındaki parametre uyumsuzluğunu düzelt

-- 1. Eski trigger'ı kaldır
DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;
DROP FUNCTION IF EXISTS send_push_on_notification();

-- 2. Yeni push notification fonksiyonu (user_id ile çalışır)
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER AS $$
DECLARE
  function_url TEXT;
  anon_key TEXT;
  http_response extensions.http_request;
  should_send_push BOOLEAN;
BEGIN
  -- Varsayılan olarak push gönder
  should_send_push := TRUE;
  
  -- Sipariş durum bildirimleri için push gönderme
  IF NEW.type IN (
    'order_update', 'order_status', 'confirmed', 'on_the_way', 'delivered',
    'order_confirmed', 'order_on_the_way', 'order_delivered'
  ) THEN
    should_send_push := FALSE;
  END IF;
  
  -- Push gönderilmeyecekse çık
  IF should_send_push = FALSE THEN
    RETURN NEW;
  END IF;
  
  -- Supabase Edge Function URL
  function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
  
  -- Supabase anon key
  anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';
  
  -- Edge Function'ı çağır (async, timeout 5 saniye)
  -- user_id, title, body parametrelerini gönder
  BEGIN
    SELECT * INTO http_response
    FROM extensions.http_post(
      url := function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || anon_key
      ),
      body := jsonb_build_object(
        'user_id', NEW.user_id,
        'title', COALESCE(NEW.title, 'Bildirim'),
        'body', COALESCE(NEW.content, ''),
        'data', jsonb_build_object(
          'notification_id', NEW.id,
          'type', NEW.type
        )
      ),
      timeout_milliseconds := 5000
    );
    
    RAISE LOG 'Push notification sent for user %: %', NEW.user_id, http_response;
    
  EXCEPTION WHEN OTHERS THEN
    -- Hata olursa log tut ama trigger'ı engelleme
    RAISE LOG 'Push notification failed for user %: %', NEW.user_id, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. Trigger'ı oluştur
CREATE TRIGGER notifications_push_trigger
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION send_push_on_notification();

-- 4. HTTP extension kontrol
SELECT 
    extname as extension_name,
    CASE 
        WHEN extname IS NOT NULL THEN '✅ Installed'
        ELSE '❌ Not found'
    END as status
FROM pg_extension 
WHERE extname = 'http';

-- 5. Trigger kontrol
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'notifications'
AND trigger_name = 'notifications_push_trigger';

-- 6. Test için verification_code insert (test etmek için uncomment edin)
-- INSERT INTO notifications (user_id, type, title, content)
-- VALUES ('test-user-id', 'verification_code', 'Test Onay Kodu', 'Kod: 123456');

DO $$
BEGIN
    RAISE NOTICE '✅ Push notification trigger updated!';
    RAISE NOTICE '✅ Now sends user_id instead of fcm_token';
END $$;

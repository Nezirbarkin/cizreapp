-- ============================================================================
-- FIX: Push bildirim edge function çağrılmıyor
-- ============================================================================
-- Sorun: Trigger aktif, FCM token var, ama Edge Function log boş
-- Çözüm: pg_net extension ile async HTTP POST

-- 1. pg_net extension kontrolü
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
        RAISE NOTICE '✅ pg_net extension mevcut';
    ELSE
        RAISE WARNING '⚠️ pg_net bulunamadı';
    END IF;
END $$;

-- 2. Eski trigger ve fonksiyonu sil
DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;
DROP FUNCTION IF EXISTS send_push_on_notification() CASCADE;

-- 3. pg_net ile async HTTP POST fonksiyonu
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER AS $$
DECLARE
  edge_function_url TEXT;
  anon_key TEXT;
  push_enabled BOOLEAN;
  user_has_fcm BOOLEAN;
  request_id BIGINT;
BEGIN
  -- 1. Bildirim tipine göre push gönderme kararı
  push_enabled := TRUE;

  IF NEW.type IN (
    'order_update', 'order_status', 'confirmed', 'on_the_way', 'delivered',
    'order_confirmed', 'order_on_the_way', 'order_delivered'
  ) THEN
    push_enabled := FALSE;
  END IF;

  IF NOT push_enabled THEN
    RETURN NEW;
  END IF;

  -- 2. Kullanıcının FCM token'ı var mı kontrol et
  SELECT (fcm_token IS NOT NULL AND fcm_token != '') INTO user_has_fcm
  FROM profiles
  WHERE id = NEW.user_id;

  IF NOT COALESCE(user_has_fcm, FALSE) THEN
    RAISE LOG '⚠️ No FCM token for user: %', NEW.user_id;
    RETURN NEW;
  END IF;

  -- 3. Edge Function URL ve anahtar
  edge_function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
  anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';

  -- 4. pg_net ile async HTTP POST
  BEGIN
    SELECT net.http_post(
      url := edge_function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || anon_key
      )::jsonb,
      body := jsonb_build_object(
        'user_id', NEW.user_id::text,
        'title', COALESCE(NEW.title, 'Bildirim'),
        'body', COALESCE(NEW.content, ''),
        'data', jsonb_build_object(
          'notification_id', NEW.id::text,
          'type', NEW.type
        )
      )::jsonb
    ) INTO request_id;

    RAISE LOG '📤 Push request sent: request_id=%, user_id=%, type=%', request_id, NEW.user_id, NEW.type;

  EXCEPTION WHEN OTHERS THEN
    RAISE LOG '❌ pg_net error: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, net;

-- 4. Trigger'ı oluştur
CREATE TRIGGER notifications_push_trigger
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION send_push_on_notification();

-- 5. Test bildirimi
DO $$
DECLARE
    v_test_user_id UUID;
BEGIN
    SELECT id INTO v_test_user_id
    FROM profiles
    WHERE fcm_token IS NOT NULL AND fcm_token != ''
    LIMIT 1;

    IF FOUND THEN
        INSERT INTO notifications (user_id, type, title, content)
        VALUES (v_test_user_id, 'verification_code', '🧪 Push Test', 'Bu bir test bildirimidir.');

        RAISE NOTICE '✅ Test bildirimi gönderildi: user_id=%', v_test_user_id;
    END IF;
END $$;

-- 6. Kontrol sorgusu (manuel çalıştırın)
-- SELECT * FROM net._http_response ORDER BY created DESC LIMIT 10;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE 'PUSH NOTIFICATION SİSTEMİ KURULDU';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE '';
    RAISE NOTICE 'Edge Function loglarını kontrol edin:';
    RAISE NOTICE 'Dashboard > Edge Functions > send-push-notification > Logs';
    RAISE NOTICE '';
    RAISE NOTICE 'pg_net isteklerini kontrol etmek için:';
    RAISE NOTICE 'SELECT * FROM net._http_response ORDER BY created DESC LIMIT 10;';
    RAISE NOTICE '═══════════════════════════════════════════════';
END $$;

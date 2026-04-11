-- ============================================================================
-- COMPLETE FIX: Push Notification System
-- ============================================================================
-- Hiçbir push bildirim gelmiyor - tam sistem kontrolü ve düzeltme

-- 1. HTTP extension kontrol ve yükle
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = 'http'
    ) THEN
        -- http extension'ı yükle
        -- Not: Bu için SuperUser yetkisi gerekebilir
        RAISE WARNING '⚠️ HTTP extension bulunamadı!';
        RAISE WARNING 'Lütfen önce http extension''ını yükleyin:';
        RAISE WARNING '  CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;';
    ELSE
        RAISE NOTICE '✅ HTTP extension mevcut';
    END IF;
END $$;

-- 2. Eski trigger ve fonksiyonları temizle
DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;
DROP TRIGGER IF EXISTS send_push_on_notification ON notifications;
DROP FUNCTION IF EXISTS send_push_on_notification();

-- 3. Yeni push notification fonksiyonu (basitleştirilmiş ve hata ayıklamalı)
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER AS $$
DECLARE
  edge_function_url TEXT;
  service_role_key TEXT;
  http_response extensions.http_request;
  push_enabled BOOLEAN;
  user_has_fcm BOOLEAN;
BEGIN
  -- 1. Bildirim tipine göre push gönderme kararı
  push_enabled := TRUE;
  
  IF NEW.type IN (
    'order_update', 'order_status', 'confirmed', 'on_the_way', 'delivered',
    'order_confirmed', 'order_on_the_way', 'order_delivered'
  ) THEN
    push_enabled := FALSE;
    RAISE LOG '⏭️ Push skipped for order status type: %', NEW.type;
  END IF;
  
  -- 2. Kullanıcının FCM token'ı var mı kontrol et
  SELECT (fcm_token IS NOT NULL AND fcm_token != '') INTO user_has_fcm
  FROM profiles
  WHERE id = NEW.user_id;
  
  IF NOT COALESCE(user_has_fcm, FALSE) THEN
    RAISE LOG '⚠️ No FCM token for user %, push skipped', NEW.user_id;
    RETURN NEW;
  END IF;
  
  -- 3. Push gönderilmeyecekse çık
  IF NOT push_enabled THEN
    RETURN NEW;
  END IF;
  
  -- 4. Edge Function URL ve anahtar
  edge_function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
  
  -- Service Role Key kullan (anon key yerine)
  service_role_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODkzMjczOCwiZXhwIjoyMDg0NTA4NzM4fQ.Xs1l_0MqO4K8J8Zf-0qKsN7pR8c5zKZ3yW8xM8l3xC8';
  
  -- 5. Edge Function'ı çağır (async)
  BEGIN
    RAISE LOG '📤 Sending push: user_id=%, type=%, title=%', NEW.user_id, NEW.type, COALESCE(NEW.title, '(no title)');
    
    SELECT * INTO http_response
    FROM extensions.http_post(
      url := edge_function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key
      ),
      body := jsonb_build_object(
        'user_id', NEW.user_id::text,
        'title', COALESCE(NEW.title, 'Bildirim'),
        'body', COALESCE(NEW.content, ''),
        'data', jsonb_build_object(
          'notification_id', NEW.id::text,
          'type', NEW.type
        )
      ),
      timeout_milliseconds := 5000
    );
    
    -- Yanıtı logla
    RAISE LOG '✅ Push response: status=%, body=%', 
        COALESCE(http_response.status, 'null'),
        COALESCE(http_response::text, 'null');
        
  EXCEPTION WHEN OTHERS THEN
    RAISE LOG '❌ Push failed: user_id=%, error=%', NEW.user_id, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 4. Trigger'ı oluştur
CREATE TRIGGER notifications_push_trigger
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION send_push_on_notification();

-- 5. Edge Function deploy kontrolü için SQL
SELECT 
    'Edge Function' as component,
    'send-push-notification' as name,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_tables 
            WHERE tablename = 'notifications'
        ) THEN '⚠️ Deploy edilmeli!'
        ELSE '❌'
    END as status;

-- 6. Test bildirimi (mevcut bir kullanıcı ile)
DO $$
DECLARE
    v_test_user_id UUID;
    v_has_users BOOLEAN;
BEGIN
    -- Mevcut bir kullanıcı bul
    SELECT id INTO v_test_user_id
    FROM profiles
    WHERE fcm_token IS NOT NULL AND fcm_token != ''
    LIMIT 1;
    
    IF FOUND THEN
        RAISE NOTICE '📱 Test kullanıcı bulundu: %', v_test_user_id;
        
        -- Test bildirimi ekle
        INSERT INTO notifications (user_id, type, title, content)
        VALUES (v_test_user_id, 'verification_code', '🧪 Test Bildirimi', 'Bu bir test bildirimidir. Push görmelisiniz!');
        
        RAISE NOTICE '✅ Test bildirimi eklendi. Push gelmeli!';
    ELSE
        RAISE WARNING '⚠️ FCM token''ı olan kullanıcı bulunamadı!';
        RAISE WARNING 'Lütfen önce kullanıcı FCM token''ını kaydedin.';
    END IF;
END $$;

-- 7. Sistem durumu özeti
SELECT 
    'Push Notification System Status' as status_report;

-- Extension durumu
SELECT 
    'HTTP Extension' as component,
    extname as name,
    CASE WHEN extname IS NOT NULL THEN '✅ Installed' ELSE '❌ Missing' END as status
FROM pg_extension 
WHERE extname = 'http'
UNION ALL
-- Trigger durumu
SELECT 
    'Trigger' as component,
    trigger_name as name,
    '✅ Active' as status
FROM information_schema.triggers 
WHERE event_object_table = 'notifications'
AND trigger_name = 'notifications_push_trigger'
UNION ALL
-- FCM token sayısı
SELECT 
    'FCM Tokens' as component,
    COUNT(*)::text as name,
    CASE WHEN COUNT(*) > 0 THEN '✅ Found' ELSE '❌ None' END as status
FROM profiles 
WHERE fcm_token IS NOT NULL AND fcm_token != '';

-- 8. Manuel deploy talimatları
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
    RAISE NOTICE 'PUSH NOTIFICATION SİSTEMİ KURULUM TAMAMLANDI';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
    RAISE NOTICE '';
    RAISE NOTICE 'Eğer hala bildirim gelmiyorsa:';
    RAISE NOTICE '1. Edge Function''ı deploy edin:';
    RAISE NOTICE '   supabase functions deploy send-push-notification';
    RAISE NOTICE '';
    RAISE NOTICE '2. Edge Function loglarını kontrol edin:';
    RAISE NOTICE '   supabase functions logs send-push-notification';
    RAISE NOTICE '';
    RAISE NOTICE '3. FCM token kaydedilmiş kullanıcı olup olmadığını kontrol edin:';
    RAISE NOTICE '   SELECT id, username, fcm_token FROM profiles WHERE fcm_token IS NOT NULL;';
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
END $$;

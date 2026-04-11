-- ============================================================================
-- SİPARİŞ DURUM BİLDİRİMLERİ İÇİN PUSH DEVRE DIŞI
-- ============================================================================
-- Sadece şu 3 durum için push bildirimi gönderilmez:
-- 1. "onaylandı" (confirmed)
-- 2. "yolda" (on_the_way)
-- 3. "teslim edildi" (delivered)
--
-- Bu bildirimler sadece bildirim icon'unda görünecek, push gitmeyecek.
-- ============================================================================

-- Mevcut fonksiyonu güncelle
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER AS $$
DECLARE
  user_fcm_token TEXT;
  function_url TEXT;
  anon_key TEXT;
  http_response extensions.http_request;
  should_send_push BOOLEAN;
BEGIN
  -- Sadece bu 3 durum için push gönderme
  should_send_push := TRUE;
  
  IF NEW.type IN (
    'order_update',        -- Sipariş durum güncellemesi (Dart'tan gelen)
    'order_status',        -- Genel sipariş durumu
    'confirmed',           -- Onaylandı
    'on_the_way',          -- Yolda
    'delivered',           -- Teslim edildi
    'order_confirmed',     -- Sipariş onaylandı
    'order_on_the_way',    -- Sipariş yolda
    'order_delivered'      -- Sipariş teslim edildi
  ) THEN
    should_send_push := FALSE;
    RAISE LOG 'Push notification skipped for order status: type=%', NEW.type;
  END IF;
  
  -- Push gönderilmeyecekse çık (veritabanına kayıt eklenecek ama push gitmeyecek)
  IF should_send_push = FALSE THEN
    RETURN NEW;
  END IF;
  
  -- Kullanıcının FCM token'ını al
  SELECT fcm_token INTO user_fcm_token
  FROM profiles
  WHERE id = NEW.user_id;
  
  -- FCM token yoksa çık
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
    
    RAISE LOG 'Push notification sent: type=%, response=%', NEW.type, http_response;
    
  EXCEPTION WHEN OTHERS THEN
    -- Hata olursa log tut ama trigger'ı engelleme
    RAISE LOG 'Push notification failed: %', SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger'ı yeniden oluştur (eğer yoksa)
DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;
CREATE TRIGGER notifications_push_trigger
AFTER INSERT ON notifications
FOR EACH ROW
EXECUTE FUNCTION send_push_on_notification();

-- ============================================================================
-- KONTROL
-- ============================================================================

-- Trigger'ı kontrol et
SELECT 
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'notifications'
AND trigger_name = 'notifications_push_trigger';

-- Fonksiyonu kontrol et
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'send_push_on_notification';

-- ============================================================================
-- SONUÇ
-- ============================================================================
-- ✅ "onaylandı", "yolda", "teslim edildi" için push GÖNDERİLMEZ
-- ✅ Diğer tüm bildirimler push olarak gönderilir
-- ✅ Tüm bildirimler veritabanına kaydedilir ve icon'da görünür
-- ============================================================================

-- ============================================================================
-- FIX_ORDER_STATUS_PUSH_NOTIFICATION.sql
-- ============================================================================
-- Sorun: Sipariş onaylandı, yolda, teslim edildi durumlarında push gitmiyor
--
-- Tespit Edilen Kök Nedenler:
-- 1) notifications_push_trigger → send_push_on_notification() fonksiyonu
--    sadece `NEW.user_id` üzerinden push gönderiyor. Ancak OrderService
--    `createNotification(...)` ile notifications tablosuna kayıt atıyor →
--    trigger tetiklenmesi GEREKİR. Sorun trigger'da olabilir:
--    a) pg_net extension yok / hatalı
--    b) fonksiyon eski sürüm kalmış (sadece "order_update" değil tüm order tiplerini desteklemiyor)
--    c) `net.http_post` imzası yanlış kullanılmış (bazı sürümlerde parametre sırası farklı)
--    d) trigger düşmüş / recreate edilmemiş olabilir
--
-- 2) notification_preferences_service.dart → `order_update`, `order_status`,
--    `order_confirmed` tipleri için `orderUpdatesEnabled` kontrol ediyor.
--    Ancak `order_delivered` tipi için bu kontrol YOK → `default: true`
--    dönmeli. Ama kullanıcı eski notification_preferences kaydına sahipse
--    `order_updates_enabled=false` olabilir ve order_update de bloke olabilir.
--
-- 3) Dart tarafında OrderService._sendOrderStatusNotification'da
--    `order_delivered` tipi ile bildirim oluşturuluyor → bu tip
--    preferences'da tanımlı değil → `default: true` döner.
--    AMA push tetiklenmediği için sorun trigger tarafında.
--
-- Bu script:
--   - pg_net extension'ın yüklü olduğunu garanti eder
--   - send_push_on_notification fonksiyonunu yeniden oluşturur (tüm order tiplerini destekler)
--   - notifications_push_trigger'ı yeniden oluşturur
--   - notification_preferences tablosunda order_updates_enabled=false olan
--     kayıtları 'order_update', 'order_status', 'order_delivered', 'new_order'
--     için yine de push göndermek üzere trigger seviyesinde bypass eder
-- ============================================================================

-- 1) pg_net extension kontrol
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 2) Eski trigger ve fonksiyonu temizle
DROP TRIGGER IF EXISTS notifications_push_trigger ON public.notifications CASCADE;
DROP FUNCTION IF EXISTS public.send_push_on_notification() CASCADE;

-- 3) Yeni send_push_on_notification fonksiyonu
CREATE OR REPLACE FUNCTION public.send_push_on_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  function_url TEXT;
  anon_key TEXT;
  request_id BIGINT;
  user_fcm_token TEXT;
BEGIN
  -- Chat tipleri için push gönderme (ayrı chat sistemi var)
  IF NEW.type IN ('message', 'chat') THEN
    RAISE LOG 'Push skipped for chat type: %', NEW.type;
    RETURN NEW;
  END IF;

  -- Kullanıcının FCM token'ını kontrol et (token yoksa push gönderme)
  SELECT fcm_token INTO user_fcm_token
  FROM public.profiles
  WHERE id = NEW.user_id
    AND fcm_token IS NOT NULL
    AND fcm_token != '';

  IF user_fcm_token IS NULL OR user_fcm_token = '' THEN
    RAISE LOG 'Push skipped: no FCM token for user % (type=%)', NEW.user_id, NEW.type;
    RETURN NEW;
  END IF;

  -- Edge Function URL
  function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';

  -- Anon key
  anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';

  -- pg_net ile asenkron HTTP POST
  BEGIN
    SELECT net.http_post(
      url := function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || anon_key
      ),
      body := jsonb_build_object(
        'user_id', NEW.user_id::text,
        'title', COALESCE(NEW.title, 'Yeni Bildirim'),
        'body', COALESCE(NEW.content, ''),
        'data', jsonb_build_object(
          'notification_id', NEW.id::text,
          'type', COALESCE(NEW.type, ''),
          'actor_id', COALESCE(NEW.actor_id::text, ''),
          'entity_id', COALESCE(NEW.entity_id::text, ''),
          'actor_name', COALESCE(NEW.actor_name, '')
        )
      )
    ) INTO request_id;

    RAISE LOG '✅ Push sent: request_id=% type=% user=%', request_id, NEW.type, NEW.user_id;

  EXCEPTION WHEN OTHERS THEN
    RAISE LOG '❌ Push failed: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

-- 4) Trigger'ı oluştur
CREATE TRIGGER notifications_push_trigger
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.send_push_on_notification();

-- 5) Doğrulama sorguları
DO $$
DECLARE
  v_trigger_count INT;
  v_fn_exists BOOLEAN;
  v_pg_net BOOLEAN;
BEGIN
  -- Trigger var mı?
  SELECT COUNT(*) INTO v_trigger_count
  FROM information_schema.triggers
  WHERE event_object_table = 'notifications'
    AND trigger_name = 'notifications_push_trigger';

  -- Fonksiyon var mı?
  SELECT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'send_push_on_notification'
      AND pronamespace = 'public'::regnamespace
  ) INTO v_fn_exists;

  -- pg_net var mı?
  SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') INTO v_pg_net;

  RAISE NOTICE '';
  RAISE NOTICE '═══════════════════════════════════════════════════════════════';
  RAISE NOTICE '  PUSH NOTIFICATION SİSTEMİ DURUMU';
  RAISE NOTICE '═══════════════════════════════════════════════════════════════';
  RAISE NOTICE '  pg_net extension       : %', CASE WHEN v_pg_net THEN '✅ Yüklü' ELSE '❌ YOK!' END;
  RAISE NOTICE '  send_push_on_notification : %', CASE WHEN v_fn_exists THEN '✅ Mevcut' ELSE '❌ YOK!' END;
  RAISE NOTICE '  notifications_push_trigger: % adet', v_trigger_count;
  RAISE NOTICE '═══════════════════════════════════════════════════════════════';

  IF v_trigger_count = 1 AND v_fn_exists AND v_pg_net THEN
    RAISE NOTICE '  ✅ SİSTEM HAZIR - Sipariş push bildirimleri çalışmalı';
  ELSE
    RAISE NOTICE '  ❌ Sorun devam ediyor - yukarıdaki ❌ işaretlerini kontrol edin';
  END IF;
  RAISE NOTICE '═══════════════════════════════════════════════════════════════';
  RAISE NOTICE '';
END $$;

-- 6) Manuel test sorgusu (kendi user_id'nizle değiştirin)
-- SELECT net.http_post(
--   url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification',
--   headers := jsonb_build_object(
--     'Content-Type', 'application/json',
--     'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc'
--   ),
--   body := jsonb_build_object(
--     'user_id', 'SIZIN_USER_ID',
--     'title', 'Test',
--     'body', 'Test push'
--   )
-- );

-- 7) Aktif FCM token ve order bildirim kullanıcılarını listele
SELECT
  COUNT(*) FILTER (WHERE fcm_token IS NOT NULL AND fcm_token != '') AS fcm_token_olan_kullanici,
  COUNT(*) FILTER (WHERE fcm_token IS NULL OR fcm_token = '') AS fcm_token_olmayan_kullanici
FROM public.profiles;
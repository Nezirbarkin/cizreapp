-- ============================================================================
-- PUSH NOTIFICATION SETUP KONTROL - BASIT TEST
-- ============================================================================
-- Supabase SQL Editor'da çalıştır
-- ============================================================================

-- Test 1: Trigger var mı?
WITH trigger_check AS (
  SELECT COUNT(*) as trigger_count
  FROM information_schema.triggers 
  WHERE event_object_table = 'notifications' 
  AND trigger_name = 'notifications_push_trigger'
),

-- Test 2: FCM token olan kullanıcılar
fcm_check AS (
  SELECT 
    COUNT(*) as total_users,
    COUNT(fcm_token) as users_with_token
  FROM profiles
),

-- Test 3: HTTP extension var mı?
http_check AS (
  SELECT 
    CASE 
      WHEN COUNT(*) > 0 THEN 'KURULU'
      ELSE 'KURULUSUZ'
    END as http_extension_status
  FROM pg_extension
  WHERE extname = 'http'
),

-- Test 4: Son 3 notification
recent_notifications AS (
  SELECT 
    COUNT(*) as total_notifications,
    MAX(created_at) as last_notification_time
  FROM notifications
)

SELECT 
  'KONTROL SONUÇLARI' as test_name,
  'Trigger Kurulu' as kontrolu,
  (SELECT trigger_count FROM trigger_check) as sonuc,
  CASE WHEN (SELECT trigger_count FROM trigger_check) > 0 THEN '✅ TAMAM' ELSE '❌ EKSIK' END as durum

UNION ALL

SELECT 
  'KONTROL SONUÇLARI',
  'Toplam Kullanıcı',
  (SELECT total_users::text FROM fcm_check),
  (SELECT total_users::text FROM fcm_check) || ' kullanıcı'

UNION ALL

SELECT 
  'KONTROL SONUÇLARI',
  'FCM Token Sayısı',
  (SELECT users_with_token::text FROM fcm_check),
  CASE 
    WHEN (SELECT users_with_token FROM fcm_check) > 0 THEN '✅ ' || (SELECT users_with_token::text FROM fcm_check) || ' kullanıcı'
    ELSE '❌ HİÇ TOKEN YOK'
  END

UNION ALL

SELECT 
  'KONTROL SONUÇLARI',
  'HTTP Extension',
  (SELECT http_extension_status FROM http_check),
  CASE WHEN (SELECT http_extension_status FROM http_check) = 'KURULU' THEN '✅ KURULU' ELSE '❌ YOK' END

UNION ALL

SELECT 
  'KONTROL SONUÇLARI',
  'Toplam Bildirim',
  (SELECT total_notifications::text FROM recent_notifications),
  (SELECT total_notifications::text FROM recent_notifications) || ' bildirim'

UNION ALL

SELECT 
  'KONTROL SONUÇLARI',
  'Son Bildirim Tarihi',
  COALESCE((SELECT last_notification_time::text FROM recent_notifications), 'HIÇBIRI'),
  CASE WHEN (SELECT last_notification_time FROM recent_notifications) IS NOT NULL THEN (SELECT last_notification_time::text FROM recent_notifications) ELSE '❌ HİÇ BİLDİRİM YOK' END;


-- Detay: FCM Token olan kullanıcılar
SELECT 
  '---' as separator,
  'FCM TOKEN OLAN KULLANICILAR' as detay_baslik;

SELECT 
  id,
  username,
  LENGTH(fcm_token)::text || ' karakter' as token_uzunluk,
  LEFT(fcm_token, 30) || '...' as token_basi
FROM profiles 
WHERE fcm_token IS NOT NULL AND fcm_token != ''
LIMIT 5;

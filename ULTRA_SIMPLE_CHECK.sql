-- ============================================================================
-- PUSH NOTIFICATION KONTROL TESTİ - SUPER BASİT
-- ============================================================================

-- Test 1: Trigger Kontrolü
SELECT 'TRIGGER KONTROLÜ' AS test_adi,
       COUNT(*)::text AS sonuc,
       CASE WHEN COUNT(*) > 0 THEN '✅ KURULU' ELSE '❌ YOK - TRIGGER KURMALISIN!' END AS durum
FROM information_schema.triggers 
WHERE event_object_table = 'notifications' 
AND trigger_name = 'notifications_push_trigger';

-- Test 2: Kullanıcı İstatistikleri
SELECT 'KULLANICI İSTATİSTİKLERİ' AS test_adi,
       'Toplam: ' || COUNT(*)::text AS sonuc,
       'FCM Token: ' || COUNT(fcm_token)::text || ' kullanıcı' AS durum
FROM profiles;

-- Test 3: HTTP Extension
SELECT 'HTTP EXTENSION' AS test_adi,
       extname AS sonuc,
       CASE WHEN extname = 'http' THEN '✅ KURULU' ELSE '❌ YOK' END AS durum
FROM pg_extension
WHERE extname = 'http';

-- Test 4: Bildirim Sayısı
SELECT 'BİLDİRİM SAYISI' AS test_adi,
       COUNT(*)::text AS sonuc,
       'Toplam bildirim sayısı' AS durum
FROM notifications;

-- Test 5: FCM Token Olan Kullanıcılar
SELECT 'FCM TOKEN OLAN KULLANICILAR' AS test_adi,
       id AS sonuc,
       username AS durum
FROM profiles 
WHERE fcm_token IS NOT NULL AND fcm_token != ''
LIMIT 5;

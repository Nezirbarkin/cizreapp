-- ============================================================================
-- AYRI AYRI TESTLER - HERBİRİNİ AYRI AYRI ÇALIŞTIR
-- ============================================================================

-- ============================================================================
-- TEST 1: Trigger Kurulu mu?
-- ============================================================================
-- Supabase SQL Editor'da sadece BU sorguyu çalıştır ve sonucu gönder:
SELECT 
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ KURULU'
    ELSE '❌ YOK - Trigger kurulmamiş!'
  END as trigger_durumu
FROM information_schema.triggers 
WHERE event_object_table = 'notifications' 
AND trigger_name = 'notifications_push_trigger';


-- ============================================================================
-- TEST 2: Kaç Kullanıcı Var?
-- ============================================================================
-- Supabase SQL Editor'da sadece BU sorguyu çalıştır ve sonucu gönder:
SELECT COUNT(*) as toplam_kullanici FROM profiles;


-- ============================================================================
-- TEST 3: Kaç Kullanıcıda FCM Token Var?
-- ============================================================================
-- Supabase SQL Editor'da sadece BU sorguyu çalıştır ve sonucu gönder:
SELECT COUNT(*) as fcm_token_olan_kullanici_sayisi 
FROM profiles 
WHERE fcm_token IS NOT NULL AND fcm_token != '';


-- ============================================================================
-- TEST 4: HTTP Extension Kurulu mu?
-- ============================================================================
-- Supabase SQL Editor'da sadece BU sorguyu çalıştır ve sonucu gönder:
SELECT 
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ KURULU'
    ELSE '❌ YOK - HTTP extension yok!'
  END as http_extension_durumu
FROM pg_extension
WHERE extname = 'http';


-- ============================================================================
-- TEST 5: Kaç Bildirim Var?
-- ============================================================================
-- Supabase SQL Editor'da sadece BU sorguyu çalıştır ve sonucu gönder:
SELECT COUNT(*) as toplam_bildirim_sayisi FROM notifications;


-- ============================================================================
-- TEST 6: Son 3 Bildirim
-- ============================================================================
-- Supabase SQL Editor'da sadece BU sorguyu çalıştır ve sonucu gönder:
SELECT id, user_id, type, title, created_at 
FROM notifications 
ORDER BY created_at DESC 
LIMIT 3;

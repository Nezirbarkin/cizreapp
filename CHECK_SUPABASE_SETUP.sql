-- ============================================================================
-- PUSH NOTIFICATION SİSTEM KONTROL TESTİ
-- ============================================================================
-- Bu SQL'i Supabase SQL Editor'da çalıştır ve sonuçları bana gönder
-- ============================================================================

-- 1. TRIGGER KONTROLÜ: Push notification trigger'ı kurulu mu?
SELECT '================================================' AS info;
SELECT '1. TRIGGER KONTROLÜ' AS kontrol;
SELECT '------------------------------------------------' AS info;
SELECT trigger_name, event_manipulation, action_statement, event_object_table
FROM information_schema.triggers 
WHERE event_object_table = 'notifications';

-- Eğer boş sonuç dönüyorsa, trigger kurulu DEĞİL demektir!


-- 2. FCM TOKEN KONTROLÜ: Kullanıcılarda FCM token kayıtlı mı?
SELECT '================================================' AS info;
SELECT '2. FCM TOKEN KONTROLÜ' AS kontrol;
SELECT '------------------------------------------------' AS info;
SELECT id, username, 
       CASE 
         WHEN fcm_token IS NOT NULL THEN '✅ VAR'
         ELSE '❌ YOK'
       END AS fcm_durumu,
       LEFT(fcm_token, 20) || '...' AS fcm_token_basi
FROM profiles 
ORDER BY fcm_token IS NULL, username
LIMIT 10;

-- Eğer hepsinde "❌ YOK" yazıyorsa, Flutter uygulamasında FCM token kaydedilmemiş!


-- 3. NOTIFICATIONS TABLOSU KONTROLÜ
SELECT '================================================' AS info;
SELECT '3. NOTIFICATIONS TABLOSU KONTROLÜ' AS kontrol;
SELECT '------------------------------------------------' AS info;
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'notifications'
ORDER BY ordinal_position;

-- notifications tablosunun yapısını gösterir


-- 4. SON BİLDİRİMLER: Son gönderilen bildirimler
SELECT '================================================' AS info;
SELECT '4. SON BİLDİRİMLER' AS kontrol;
SELECT '------------------------------------------------' AS info;
SELECT id, user_id, type, title, 
       LEFT(content, 50) || '...' AS content,
       created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 5;

-- Son bildirimleri gösterir


-- 5. PROFILES TABLOSUNDA FCM TOKEN KOLONU VAR MI?
SELECT '================================================' AS info;
SELECT '5. PROFILES TABLOSU YAPISI' AS kontrol;
SELECT '------------------------------------------------' AS info;
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'profiles' AND column_name = 'fcm_token';

-- fcm_token kolonu var mı kontrol eder


-- 6. HTTP EXTENSION KURULU MU?
SELECT '================================================' AS info;
SELECT '6. HTTP EXTENSION KONTROLÜ' AS kontrol;
SELECT '------------------------------------------------' AS info;
SELECT extname, extversion
FROM pg_extension
WHERE extname = 'http';

-- HTTP extension Edge Function çağırmak için gerekli


-- 7. TOPLAM KULLANICI VE TOKEN İSTATİSTİĞİ
SELECT '================================================' AS info;
SELECT '7. TOPLAM İSTATİSTİKLER' AS kontrol;
SELECT '------------------------------------------------' AS info;
SELECT 
  COUNT(*) AS toplam_kullanici,
  COUNT(fcm_token) AS fcm_token_olan,
  COUNT(*) - COUNT(fcm_token) AS fcm_token_olmayan
FROM profiles;


-- 8. FCM TOKEN OLAN KULLANICILAR DETAYLI
SELECT '================================================' AS info;
SELECT '8. FCM TOKEN OLAN KULLANICILAR' AS kontrol;
SELECT '------------------------------------------------' AS info;
SELECT id, username, 
       LENGTH(fcm_token) AS token_uzunlugu,
       fcm_token
FROM profiles 
WHERE fcm_token IS NOT NULL AND fcm_token != '';


-- TAMAMLANDI
SELECT '================================================' AS info;
SELECT '✅ KONTROL TAMAMLANDI - Tüm sonuçları kopyala ve bana gönder!' AS bilgi;
SELECT '================================================' AS info;

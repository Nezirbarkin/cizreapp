-- ============================================================================
-- PUSH BİLDİRİM SİSTEMİ - TAM DEBUĞ
-- ============================================================================
-- Bu SQL'i Supabase Dashboard > SQL Editor'de çalıştırın
-- Sonuçları bana paylaşın
-- ============================================================================

-- 1. notifications tablosu var mı ve son 10 bildirim neler?
SELECT '=== 1. SON 10 BİLDİRİM ===' AS bilgi;
SELECT id, user_id, type, title, content, actor_id, entity_id, is_read, created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 10;

-- 2. notifications tablosundaki trigger'lar neler?
SELECT '=== 2. NOTIFICATIONS TRIGGER LISTESI ===' AS bilgi;
SELECT trigger_name, event_manipulation, action_statement, action_timing
FROM information_schema.triggers
WHERE event_object_table = 'notifications'
AND trigger_schema = 'public';

-- 3. orders tablosundaki trigger'lar neler?
SELECT '=== 3. ORDERS TRIGGER LISTESI ===' AS bilgi;
SELECT trigger_name, event_manipulation, action_statement, action_timing
FROM information_schema.triggers
WHERE event_object_table = 'orders'
AND trigger_schema = 'public';

-- 4. send_push_on_notification fonksiyonu var mı?
SELECT '=== 4. PUSH FONKSIYONU VAR MI? ===' AS bilgi;
SELECT routine_name, routine_type, external_language
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN ('send_push_on_notification', 'send_fcm_push_notification', 'notify_new_order');

-- 5. send_push_on_notification fonksiyonunun kaynağı
SELECT '=== 5. PUSH FONKSIYONU KAYNAK KODU ===' AS bilgi;
SELECT prosrc FROM pg_proc WHERE proname = 'send_push_on_notification';

-- 6. http extension yüklü mü?
SELECT '=== 6. HTTP EXTENSION YUKLU MU? ===' AS bilgi;
SELECT extname, extversion FROM pg_extension WHERE extname IN ('http', 'pg_net');

-- 7. Profillerde FCM token var mı? (En az 1 kullanıcıda)
SELECT '=== 7. FCM TOKEN DURUMU ===' AS bilgi;
SELECT 
  COUNT(*) AS toplam_kullanici,
  COUNT(fcm_token) AS fcm_token_olan,
  COUNT(*) - COUNT(fcm_token) AS fcm_token_olmayan
FROM profiles;

-- 8. FCM token olan kullanıcılar (ilk 5)
SELECT '=== 8. FCM TOKEN OLAN KULLANICILAR ===' AS bilgi;
SELECT id, username, LEFT(fcm_token, 40) AS fcm_token_kismi
FROM profiles
WHERE fcm_token IS NOT NULL AND fcm_token != ''
LIMIT 5;

-- 9. Son 5 new_order bildirimi (satıcıya giden)
SELECT '=== 9. SON 5 NEW_ORDER BİLDİRİMİ ===' AS bilgi;
SELECT id, user_id, type, title, content, actor_id, entity_id, created_at
FROM notifications
WHERE type = 'new_order'
ORDER BY created_at DESC
LIMIT 5;

-- 10. notify_new_order fonksiyonu var mı ve kaynak kodu
SELECT '=== 10. NOTIFY_NEW_ORDER FONKSIYONU ===' AS bilgi;
SELECT prosrc FROM pg_proc WHERE proname = 'notify_new_order';

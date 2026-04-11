-- =====================================================
-- MEVCUT DURUMU TAM KONTROL
-- =====================================================

-- 1. notification_preferences tablo yapısı
SELECT 
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'notification_preferences'
ORDER BY column_name;

-- 2. Tüm fonksiyonlar
SELECT 
    routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name LIKE '%push%' OR routine_name LIKE '%fcm%' OR routine_name LIKE '%notif%'
ORDER BY routine_name;

-- 3. Notifications tablosu trigger'ları
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
AND event_object_table = 'notifications'
ORDER BY trigger_name;

-- 4. Edge Function listesi (eğer Supabase'de varsa)
-- Bu sadece supabase CLI ile kontrol edilebilir

-- 5. Son 5 bildirim
SELECT 
    id,
    user_id,
    type,
    title,
    content,
    created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 5;

-- 6. Vault'taki secretlar
SELECT name, description FROM vault.secrets ORDER BY name;

-- 7. send_push_on_notification fonksiyonunun kaynağı
SELECT prosrc FROM pg_proc WHERE proname = 'send_push_on_notification';

-- 8. send_fcm_push_notification fonksiyonunun kaynağı
SELECT prosrc FROM pg_proc WHERE proname = 'send_fcm_push_notification';

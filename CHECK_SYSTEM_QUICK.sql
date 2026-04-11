-- =====================================================
-- SİSTEM HIZLI KONTROL - Tablo, Fonksiyon, Trigger
-- =====================================================

-- 1. TABLOLARIN VARLIĞI
SELECT 
    table_name,
    CASE 
        WHEN table_name IN ('fcm_tokens', 'device_tokens') THEN 'Push Token Tablosu'
        WHEN table_name = 'notification_tokens' THEN 'Notification Token Tablosu'
        WHEN table_name = 'notifications' THEN 'Notifications Tablosu'
        WHEN table_name = 'notification_preferences' THEN 'Notification Preferences'
        WHEN table_name = 'orders' THEN 'Orders Tablosu'
        WHEN table_name = 'shops' THEN 'Shops Tablosu'
        WHEN table_name = 'email_settings' THEN 'Email Settings'
    END as aciklama
FROM information_schema.tables
WHERE table_schema = 'public' 
AND table_name IN (
    'fcm_tokens', 'device_tokens', 'notification_tokens',
    'notifications', 'notification_preferences', 
    'orders', 'shops', 'email_settings'
)
ORDER BY table_name;

-- 2. FONKSİYONLAR (Push ve Email ile ilgili)
SELECT 
    routine_name,
    routine_type,
    data_type as return_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND (
    routine_name ILIKE '%push%' 
    OR routine_name ILIKE '%notification%'
    OR routine_name ILIKE '%fcm%'
    OR routine_name ILIKE '%email%'
    OR routine_name ILIKE '%order%'
)
ORDER BY routine_name;

-- 3. TRIGGER'LAR (Orders ve Notifications)
SELECT 
    event_object_table as table_name,
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
AND event_object_table IN ('orders', 'notifications', 'order_items')
ORDER BY event_object_table, trigger_name;

-- 4. EXTENSIONS
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('pg_net', 'http', 'pgsodium', 'pg_cron')
ORDER BY extname;

-- 5. NOTIFICATION_TOKENS TABLOSU YAPISI
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'notification_tokens'
ORDER BY ordinal_position;

-- 6. ORDERS TABLOSU YAPISI
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'orders'
ORDER BY ordinal_position;

-- 7. EMAIL_SETTINGS TABLOSU YAPISI (varsa)
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'email_settings'
ORDER BY ordinal_position;

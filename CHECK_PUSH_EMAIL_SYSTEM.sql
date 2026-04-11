-- =====================================================
-- PUSH BİLDİRİM VE EMAIL SİSTEMİ KONTROL SORGUSU
-- =====================================================
-- Bu SQL'i Supabase SQL Editor'da çalıştırın ve sonuçları paylaşın

-- 1. FCM TOKEN TABLOSU KONTROLÜ
-- =====================================================
SELECT 
    'FCM_TOKENS_TABLE' as check_name,
    EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'fcm_tokens'
    ) as exists,
    (SELECT COUNT(*) FROM fcm_tokens) as total_tokens
WHERE EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'fcm_tokens'
)
UNION ALL
SELECT 
    'DEVICE_TOKENS_TABLE' as check_name,
    EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'device_tokens'
    ) as exists,
    (SELECT COUNT(*) FROM device_tokens) as total_tokens
WHERE EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'device_tokens'
);

-- 2. FCM/DEVICE TOKEN TABLOSU YAPISI
-- =====================================================
SELECT 
    'FCM_TOKENS_SCHEMA' as info_type,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'fcm_tokens'
ORDER BY ordinal_position;

SELECT 
    'DEVICE_TOKENS_SCHEMA' as info_type,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'device_tokens'
ORDER BY ordinal_position;

-- 3. NOTIFICATIONS TABLOSU KONTROLÜ
-- =====================================================
SELECT 
    'NOTIFICATIONS_TABLE' as check_name,
    EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'notifications'
    ) as exists,
    CASE 
        WHEN EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'notifications')
        THEN (SELECT COUNT(*) FROM notifications)
        ELSE 0
    END as total_notifications;

-- 4. NOTIFICATIONS TABLOSU YAPISI
-- =====================================================
SELECT 
    'NOTIFICATIONS_SCHEMA' as info_type,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'notifications'
ORDER BY ordinal_position;

-- 5. ORDERS TABLOSU KONTROLÜ
-- =====================================================
SELECT 
    'ORDERS_TABLE' as check_name,
    EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'orders'
    ) as exists,
    CASE 
        WHEN EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'orders')
        THEN (SELECT COUNT(*) FROM orders)
        ELSE 0
    END as total_orders;

-- 6. ORDERS TABLOSU YAPISI (email alanları var mı?)
-- =====================================================
SELECT 
    'ORDERS_SCHEMA' as info_type,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'orders'
ORDER BY ordinal_position;

-- 7. SHOPS TABLOSU KONTROLÜ (shop email alanı var mı?)
-- =====================================================
SELECT
    'SHOPS_SCHEMA' as info_type,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'shops'
AND (column_name ILIKE '%email%' OR column_name ILIKE '%contact%')
ORDER BY ordinal_position;

-- 8. PROFILES TABLOSU EMAIL KONTROLÜ
-- =====================================================
SELECT 
    'PROFILES_EMAIL_FIELD' as info_type,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'profiles'
AND column_name ILIKE '%email%';

-- 9. PUSH NOTIFICATION FONKSİYONLARI
-- =====================================================
SELECT 
    'PUSH_FUNCTIONS' as info_type,
    routine_name as function_name,
    routine_type,
    data_type as return_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND (
    routine_name ILIKE '%push%' 
    OR routine_name ILIKE '%notification%'
    OR routine_name ILIKE '%fcm%'
)
ORDER BY routine_name;

-- 10. EMAIL FONKSİYONLARI
-- =====================================================
SELECT 
    'EMAIL_FUNCTIONS' as info_type,
    routine_name as function_name,
    routine_type,
    data_type as return_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name ILIKE '%email%'
ORDER BY routine_name;

-- 11. ORDERS TRIGGER'LARI
-- =====================================================
SELECT 
    'ORDERS_TRIGGERS' as info_type,
    trigger_name,
    event_manipulation as trigger_event,
    action_timing as trigger_timing,
    action_statement as trigger_action
FROM information_schema.triggers
WHERE event_object_table = 'orders'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- 12. NOTIFICATION TRIGGER'LARI
-- =====================================================
SELECT 
    'NOTIFICATION_TRIGGERS' as info_type,
    event_object_table as table_name,
    trigger_name,
    event_manipulation as trigger_event,
    action_timing as trigger_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
AND (
    trigger_name ILIKE '%notif%' 
    OR trigger_name ILIKE '%push%'
    OR action_statement ILIKE '%notification%'
)
ORDER BY event_object_table, trigger_name;

-- 13. POSTGRESQL EXTENSIONS (pg_net, http vb.)
-- =====================================================
SELECT 
    'EXTENSIONS' as info_type,
    extname as extension_name,
    extversion as version
FROM pg_extension
WHERE extname IN ('pg_net', 'http', 'pg_cron', 'pgsodium')
ORDER BY extname;

-- 14. SUPABASE VAULT SECRETS (sadece varlık kontrolü)
-- =====================================================
SELECT 
    'VAULT_SECRETS' as info_type,
    COUNT(*) as secret_count
FROM vault.secrets
WHERE name ILIKE '%fcm%' 
   OR name ILIKE '%firebase%'
   OR name ILIKE '%email%'
   OR name ILIKE '%smtp%';

-- 15. EDGE FUNCTIONS KONTROLÜ (supabase_functions schema)
-- =====================================================
SELECT 
    'EDGE_FUNCTIONS' as info_type,
    routine_name as function_name
FROM information_schema.routines
WHERE routine_schema = 'supabase_functions'
ORDER BY routine_name;

-- 16. SON 10 NOTIFICATION KAYDI (varsa)
-- =====================================================
SELECT 
    'RECENT_NOTIFICATIONS' as info_type,
    id,
    user_id,
    type,
    title,
    body,
    created_at,
    is_read
FROM notifications
ORDER BY created_at DESC
LIMIT 10;

-- 17. SON 5 SİPARİŞ KAYDI
-- =====================================================
SELECT 
    'RECENT_ORDERS' as info_type,
    id,
    user_id,
    shop_id,
    status,
    total_amount,
    created_at
FROM orders
ORDER BY created_at DESC
LIMIT 5;

-- 18. FCM TOKEN KAYITLARI ÖRNEĞİ (varsa)
-- =====================================================
SELECT 
    'FCM_TOKEN_SAMPLES' as info_type,
    id,
    user_id,
    token,
    platform,
    created_at,
    updated_at
FROM fcm_tokens
ORDER BY updated_at DESC
LIMIT 5;

SELECT 
    'DEVICE_TOKEN_SAMPLES' as info_type,
    id,
    user_id,
    token,
    platform,
    created_at,
    updated_at
FROM device_tokens
ORDER BY updated_at DESC
LIMIT 5;

-- 19. RLS POLİCY KONTROLÜ (notifications ve fcm_tokens)
-- =====================================================
SELECT 
    'RLS_POLICIES' as info_type,
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd as command,
    qual as using_expression
FROM pg_policies
WHERE tablename IN ('notifications', 'fcm_tokens', 'device_tokens', 'orders')
ORDER BY tablename, policyname;

-- 20. NOTIFICATION PREFERENCES TABLOSU (varsa)
-- =====================================================
SELECT 
    'NOTIFICATION_PREFERENCES_TABLE' as check_name,
    EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'notification_preferences'
    ) as exists;

SELECT 
    'NOTIFICATION_PREFERENCES_SCHEMA' as info_type,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'notification_preferences'
ORDER BY ordinal_position;

-- =====================================================
-- SONUÇ: Tüm sonuçları kopyalayıp bana gönderin
-- =====================================================

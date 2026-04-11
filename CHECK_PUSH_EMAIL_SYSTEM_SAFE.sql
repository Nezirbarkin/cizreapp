-- =====================================================
-- PUSH BİLDİRİM VE EMAIL SİSTEMİ KONTROL SORGUSU (SAFE VERSION)
-- =====================================================
-- Bu SQL'i Supabase SQL Editor'da çalıştırın

-- 1. TABLOLARIN VARLIĞINI KONTROL ET
-- =====================================================
SELECT 
    table_name,
    CASE 
        WHEN table_name = 'fcm_tokens' THEN '1. FCM Tokens'
        WHEN table_name = 'device_tokens' THEN '2. Device Tokens'
        WHEN table_name = 'notifications' THEN '3. Notifications'
        WHEN table_name = 'orders' THEN '4. Orders'
        WHEN table_name = 'shops' THEN '5. Shops'
        WHEN table_name = 'profiles' THEN '6. Profiles'
        WHEN table_name = 'notification_preferences' THEN '7. Notification Preferences'
    END as table_description
FROM information_schema.tables
WHERE table_schema = 'public' 
AND table_name IN ('fcm_tokens', 'device_tokens', 'notifications', 'orders', 'shops', 'profiles', 'notification_preferences')
ORDER BY table_name;

-- 2. TÜM FONKSIYONLARI LİSTELE
-- =====================================================
SELECT 
    routine_name as function_name,
    routine_type,
    data_type as return_type,
    CASE 
        WHEN routine_name ILIKE '%push%' THEN 'PUSH'
        WHEN routine_name ILIKE '%notification%' THEN 'NOTIFICATION'
        WHEN routine_name ILIKE '%fcm%' THEN 'FCM'
        WHEN routine_name ILIKE '%email%' THEN 'EMAIL'
        WHEN routine_name ILIKE '%order%' THEN 'ORDER'
        ELSE 'OTHER'
    END as category
FROM information_schema.routines
WHERE routine_schema = 'public'
AND (
    routine_name ILIKE '%push%' 
    OR routine_name ILIKE '%notification%'
    OR routine_name ILIKE '%fcm%'
    OR routine_name ILIKE '%email%'
    OR routine_name ILIKE '%order%'
)
ORDER BY category, routine_name;

-- 3. TÜM TRİGGERLARI LİSTELE
-- =====================================================
SELECT 
    event_object_table as table_name,
    trigger_name,
    event_manipulation as event_type,
    action_timing as timing,
    SUBSTRING(action_statement, 1, 100) as action_preview
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- 4. POSTGRESQL EXTENSIONS
-- =====================================================
SELECT 
    extname as extension_name,
    extversion as version
FROM pg_extension
ORDER BY extname;

-- 5. NOTIFICATIONS TABLOSU YAPISI (varsa)
-- =====================================================
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'notifications'
ORDER BY ordinal_position;

-- 6. ORDERS TABLOSU YAPISI (varsa)
-- =====================================================
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'orders'
ORDER BY ordinal_position;

-- 7. SHOPS TABLOSU - EMAIL İLE İLGİLİ ALANLAR (varsa)
-- =====================================================
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'shops'
AND (column_name ILIKE '%email%' OR column_name ILIKE '%contact%' OR column_name ILIKE '%phone%')
ORDER BY ordinal_position;

-- 8. PROFILES TABLOSU - EMAIL ALANI (varsa)
-- =====================================================
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'profiles'
AND column_name ILIKE '%email%'
ORDER BY ordinal_position;

-- 9. RLS POLİCYLERİ
-- =====================================================
SELECT 
    tablename,
    policyname,
    permissive,
    roles::text,
    cmd as command,
    LEFT(qual::text, 50) as using_clause
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- 10. VAULT SECRETS (FCM, Firebase, Email ile ilgili)
-- =====================================================
SELECT 
    name as secret_name,
    description,
    created_at
FROM vault.secrets
WHERE name ILIKE '%fcm%' 
   OR name ILIKE '%firebase%'
   OR name ILIKE '%email%'
   OR name ILIKE '%smtp%'
ORDER BY name;

-- =====================================================
-- ÖNEMLİ: Tüm sonuçları kopyalayıp bana gönderin
-- =====================================================

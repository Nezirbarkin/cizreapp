-- ============================================
-- PUSH NOTIFICATION TRIGGER DEBUG SQL
-- Supabase SQL Editor'da çalıştırın
-- ============================================

-- 1. TRIGGER VAR MI?
SELECT 
    trigger_name,
    event_manipulation,
    action_statement,
    action_timing,
    event_object_table
FROM information_schema.triggers 
WHERE event_object_table = 'notifications'
   OR trigger_name LIKE '%push%'
   OR trigger_name LIKE '%notification%';

-- 2. TRIGGER FONKSİYONU VAR MI?
SELECT 
    proname,
    prolang,
    probin,
    CASE 
        WHEN prosrc IS NOT NULL THEN 'VAR'
        ELSE 'YOK'
    END as function_status
FROM pg_proc 
WHERE proname LIKE '%push%'
   OR proname LIKE '%send_notification%';

-- 3. HTTP EXTENSION YÜKLÜ MÜ?
SELECT 
    extname,
    extversion,
    CASE 
        WHEN extname IS NOT NULL THEN 'YÜKLÜ ✅'
        ELSE 'YÜKLÜ DEĞİL ❌'
    END as http_status
FROM pg_extension 
WHERE extname = 'http';

-- 4. NOTIFICATIONS TABLOSU YAPISI
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'notifications'
ORDER BY ordinal_position;

-- 5. SON BİLDİRİMLER (VAR MI?)
SELECT 
    id,
    user_id,
    type,
    title,
    created_at
FROM notifications 
ORDER BY created_at DESC 
LIMIT 5;

-- 6. FCM TOKEN'LAR KONTROLÜ
SELECT 
    id,
    username,
    CASE 
        WHEN fcm_token IS NULL THEN 'YOK ❌'
        WHEN LENGTH(fcm_token) < 50 THEN 'KISA/GEÇERSIZ ❌'
        ELSE CONCAT('VAR ✅ (', LEFT(fcm_token, 30), '...)')
    END as fcm_status,
    LENGTH(fcm_token) as token_length
FROM profiles 
WHERE fcm_token IS NOT NULL
LIMIT 10;

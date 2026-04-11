-- =====================================================
-- NOTIFICATIONS TABLOSU YAPISI KONTROLÜ
-- =====================================================
-- Flutter hatası: record "new" has no field "body"
-- =====================================================

-- 1. Notifications tablosu yapısı
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'notifications'
ORDER BY column_name;

-- 2. Son 10 bildirim
SELECT 
    id,
    user_id,
    type,
    title,
    created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 10;

-- 3. Notifications trigger'ları
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'notifications'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- 4. Notification preferences
SELECT 
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'notification_preferences'
ORDER BY column_name;

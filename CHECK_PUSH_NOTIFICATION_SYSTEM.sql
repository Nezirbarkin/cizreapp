-- ================================================
-- PUSH BİLDİRİM SİSTEMİ KONTROL (v3)
-- ================================================

-- 1. FCM token'ları kontrol et
SELECT 
    id,
    username,
    CASE 
        WHEN fcm_token IS NULL THEN '❌ TOKEN YOK'
        WHEN fcm_token = '' THEN '❌ TOKEN BOŞ'
        ELSE '✅ TOKEN VAR: ' || LEFT(fcm_token, 50) || '...'
    END as token_durumu
FROM profiles
WHERE fcm_token IS NOT NULL AND fcm_token != ''
ORDER BY updated_at DESC
LIMIT 10;

-- 2. Son bildirimleri kontrol et
SELECT 
    id,
    user_id,
    type,
    title,
    content,
    is_read,
    created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 20;

-- 3. Trigger'ların varlığını kontrol et
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_name LIKE '%notification%'
   OR trigger_name LIKE '%push%'
ORDER BY event_object_table, trigger_name;

-- 4. notification_preferences tablosunun kolonlarını kontrol et
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'notification_preferences'
ORDER BY ordinal_position;

-- 5. Bildirim tercihleri kontrol et (sadece temel kolonlar)
SELECT *
FROM notification_preferences
LIMIT 10;

SELECT '✅ Push bildirim sistem kontrolü tamamlandı' as sonuc;

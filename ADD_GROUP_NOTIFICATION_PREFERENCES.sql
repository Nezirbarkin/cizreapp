-- =====================================================
-- GRUP BİLDİRİM TERCİHLERİNİ EKLE
-- =====================================================
-- Bu script, notification_preferences tablosuna
-- grup ile ilgili bildirim alanlarını ekler.

-- 1. notification_preferences tablosuna grup bildirim alanlarını ekle
ALTER TABLE notification_preferences
ADD COLUMN IF NOT EXISTS group_join_requests_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS group_member_joined_enabled BOOLEAN DEFAULT true;

-- 2. Mevcut kullanıcılar için varsayılan değerleri true yap
UPDATE notification_preferences
SET
    group_join_requests_enabled = COALESCE(group_join_requests_enabled, true),
    group_member_joined_enabled = COALESCE(group_member_joined_enabled, true)
WHERE group_join_requests_enabled IS NULL OR group_member_joined_enabled IS NULL;

-- 3. Kontrol sorguları
SELECT 'Notification preferences columns added:' AS status;
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'notification_preferences'
AND column_name IN ('group_join_requests_enabled', 'group_member_joined_enabled');

SELECT 'Total users:' AS status;
SELECT COUNT(*) AS total_users FROM profiles;

SELECT 'Users with group notifications enabled:' AS status;
SELECT
    COUNT(*) FILTER (WHERE group_join_requests_enabled = true) AS join_requests_enabled,
    COUNT(*) FILTER (WHERE group_member_joined_enabled = true) AS member_joined_enabled
FROM notification_preferences;

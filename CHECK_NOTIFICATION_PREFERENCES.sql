-- =====================================================
-- NOTIFICATION PREFERENCES TABLOSU KONTROL
-- =====================================================

-- notification_preferences tablosunun tüm yapısı
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'notification_preferences'
ORDER BY column_name;

-- Mevcut veri örneği (varsa)
SELECT * FROM notification_preferences LIMIT 1;

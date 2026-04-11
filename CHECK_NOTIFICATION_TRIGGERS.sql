-- ============================================================================
-- BİLDİRİM TRIGGER'LARINI KONTROL ET
-- ============================================================================
-- Hangi trigger'lar aktif kontrol et
-- ============================================================================

-- 1. Tüm notification trigger'larını listele
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'notifications'
   OR event_object_table = 'orders'
ORDER BY event_object_table, trigger_name;

-- 2. Tüm notification fonksiyonlarını listele
SELECT 
    routine_name,
    routine_type,
    routine_definition
FROM information_schema.routines
WHERE routine_name LIKE '%notification%'
   OR routine_name LIKE '%push%'
ORDER BY routine_name;

-- 3. Orders tablosundaki trigger'lar
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'orders'
ORDER BY trigger_name;

-- ============================================================
-- NOTIFICATIONS TABLOSU ŞEMASI KONTROLÜ
-- ============================================================

-- Tüm kolonları ve constraint'leri gör
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'notifications'
ORDER BY ordinal_position;

-- Constraint'leri gör
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'public.notifications'::regclass
ORDER BY conname;

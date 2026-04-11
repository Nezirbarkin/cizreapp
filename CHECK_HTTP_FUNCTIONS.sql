-- ============================================================================
-- HTTP FONKSİYON İMZASINI BUL
-- ============================================================================

-- 1. http extension'daki fonksiyonlar
SELECT 
    p.proname AS fonksiyon_adi,
    pg_catalog.pg_get_function_arguments(p.oid) AS parametreler,
    pg_catalog.pg_get_function_result(p.oid) AS donus_tipi
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'extensions'
AND p.proname LIKE '%http%'
ORDER BY p.proname;

-- 2. net extension'daki fonksiyonlar (pg_net)
SELECT 
    p.proname AS fonksiyon_adi,
    pg_catalog.pg_get_function_arguments(p.oid) AS parametreler,
    pg_catalog.pg_get_function_result(p.oid) AS donus_tipi
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'net'
AND p.proname LIKE '%http%'
ORDER BY p.proname;

-- 3. public schema'daki http fonksiyonları
SELECT 
    p.proname AS fonksiyon_adi,
    pg_catalog.pg_get_function_arguments(p.oid) AS parametreler,
    pg_catalog.pg_get_function_result(p.oid) AS donus_tipi
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
AND p.proname LIKE '%http%'
ORDER BY p.proname;

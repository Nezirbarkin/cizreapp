-- =====================================================
-- QUERY 4: auth_is_admin() FONKSİYONU TEST
-- Bu sorguyu SQL Editor'da çalıştırıp sonucu gönderin
-- =====================================================
-- Fonksiyon var mı?
SELECT 
  p.proname AS function_name,
  pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'auth_is_admin'
AND n.nspname = 'public';

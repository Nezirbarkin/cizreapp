-- ============================================================
-- TÜM NOTIFICATIONS POLICIES KONTROLÜ
-- ============================================================

-- 1. Tüm mevcut policy'leri listele
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,      -- PERMISSIVE veya RESTRICTIVE
    roles,
    cmd,             -- INSERT, SELECT, UPDATE, DELETE
    qual,            -- USING clause
    with_check       -- WITH CHECK clause
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY cmd, policyname;

-- 2. RLS durumunu kontrol et
SELECT 
    schemaname,
    tablename,
    rowsecurity AS rls_enabled
FROM pg_tables 
WHERE tablename = 'notifications';

-- 3. Authenticated role'ün INSERT permission'ı var mı?
SELECT 
    table_name,
    privilege_type
FROM information_schema.table_privileges
WHERE table_name = 'notifications' 
  AND grantee = 'authenticated';

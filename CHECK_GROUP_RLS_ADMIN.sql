-- Grup tablolarındaki RLS politikalarını ve admin izinlerini kontrol et

-- 1. groups tablosu politikaları
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename IN ('groups', 'group_members', 'group_messages', 'group_join_requests')
ORDER BY tablename, policyname;

-- 2. Profiles tablosunda is_app_admin kolonu var mı?
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'profiles' 
  AND column_name = 'is_app_admin';

-- 3. Admin bypass için RPC fonksiyonları var mı?
SELECT 
    routine_name,
    routine_type,
    security_type
FROM information_schema.routines
WHERE routine_name LIKE '%admin%group%'
   OR routine_name LIKE '%group%admin%'
ORDER BY routine_name;

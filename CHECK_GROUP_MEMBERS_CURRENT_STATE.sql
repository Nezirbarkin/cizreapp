-- =====================================================
-- MEVCUT DURUMU KONTROL ET
-- Supabase SQL Editor'de çalıştır ve sonuçları yapıştır
-- =====================================================

-- 1. group_members tablosunun RLS durumu ve politikaları
SELECT tablename, rowsecurity as rls_enabled 
FROM pg_tables 
WHERE schemaname = 'public' AND tablename = 'group_members';

-- 2. group_members tablosundaki tüm politikalar
SELECT policyname, cmd, permissive, roles, qual, with_check 
FROM pg_policies 
WHERE schemaname = 'public' AND tablename = 'group_members'
ORDER BY policyname;

-- 3. group_join_requests tablosunun RLS durumu ve politikaları
SELECT tablename, rowsecurity as rls_enabled 
FROM pg_tables 
WHERE schemaname = 'public' AND tablename = 'group_join_requests';

-- 4. group_join_requests tablosundaki tüm politikalar
SELECT policyname, cmd, permissive, roles, qual, with_check 
FROM pg_policies 
WHERE schemaname = 'public' AND tablename = 'group_join_requests'
ORDER BY policyname;

-- 5. approve_group_join_request fonksiyonu var mı?
SELECT routine_name, routine_type 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name IN ('approve_group_join_request', 'reject_group_join_request');

-- 6. approve_group_join_request fonksiyonunun detayları
SELECT prokind, prosecdef, proconfig 
FROM pg_proc 
WHERE proname = 'approve_group_join_request' 
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
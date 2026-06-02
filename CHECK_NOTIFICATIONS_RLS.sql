-- ============================================================================
-- Mevcut notifications tablosu RLS policy'lerini kontrol et
-- Bu dosyayı Supabase SQL Editor'de çalıştır ve sonucu paylaş
-- ============================================================================

SELECT 
    policyname,
    cmd,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'notifications'
  AND schemaname = 'public'
ORDER BY cmd;

-- Ayrıca tablodaki tüm policy'leri listele
SELECT 
    polname as policy_name,
    polcmd as command,
    polpermissive as permissive,
    CASE WHEN polcmd = 'r' THEN 'SELECT'
         WHEN polcmd = 'a' THEN 'INSERT'
         WHEN polcmd = 'u' THEN 'UPDATE'
         WHEN polcmd = 'd' THEN 'DELETE'
         ELSE polcmd END as command_type
FROM pg_policy
WHERE polrelid = 'public.notifications'::regclass
ORDER BY polcmd;

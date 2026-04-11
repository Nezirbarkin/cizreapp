-- =====================================================
-- AÇIK GRUBA KATILIM SORUNU - RLS POLİTİKALARI KONTROLÜ
-- =====================================================

-- 1. Mevcut group_members INSERT politikalarını kontrol et
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
WHERE tablename = 'group_members'
AND cmd = 'INSERT'
ORDER BY policyname;

-- 2. Problemi anlama: INSERT politikası sadece adminlere izin veriyor mu?
-- "Group admins can add members" politikası var mı?
SELECT policyname, with_check 
FROM pg_policies 
WHERE tablename = 'group_members' 
AND cmd = 'INSERT';

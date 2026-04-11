-- =====================================================
-- FOLLOWS RLS POLİCY TEMİZLİĞİ
-- Duplicate policy'leri kaldır + auth_rls_initplan düzelt
-- =====================================================

-- 1. ESKİ DUPLICATE POLİCY'LERİ KALDIR
DROP POLICY IF EXISTS "follows_insert_policy" ON follows;
DROP POLICY IF EXISTS "follows_delete_policy" ON follows;

-- 2. YENİ POLİCY'LERİ PERFORMANSLI HALE GETİR
-- (select auth.uid()) kullanarak initplan uyarısını düzelt
DROP POLICY IF EXISTS "Users can follow others" ON follows;
DROP POLICY IF EXISTS "Users can unfollow" ON follows;

CREATE POLICY "Users can follow others"
ON follows FOR INSERT
WITH CHECK (
    (select auth.uid()) = follower_id 
    OR (select auth.uid()) = following_id
);

CREATE POLICY "Users can unfollow"
ON follows FOR DELETE
USING (
    (select auth.uid()) = follower_id 
    OR (select auth.uid()) = following_id
);

-- 3. DOĞRULAMA
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'follows'
ORDER BY policyname;

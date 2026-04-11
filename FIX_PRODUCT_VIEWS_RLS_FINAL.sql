-- ============================================================================
-- product_views RLS POLICY DÜZELTMELERİ (Linter uyarıları için)
-- ============================================================================

-- 1. Eski policy'leri temizle
DROP POLICY IF EXISTS "Users can insert their own product views" ON product_views;
DROP POLICY IF EXISTS "Anyone can insert product views" ON product_views;
DROP POLICY IF EXISTS "Users can view product views" ON product_views;

-- 2. Tek bir INSERT policy (subquery ile auth.uid() performans düzeltmesi)
CREATE POLICY "Users can insert their own product views"
ON product_views
FOR INSERT
TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

-- 3. SELECT policy (subquery ile)
CREATE POLICY "Users can view product views"
ON product_views
FOR SELECT
TO authenticated
USING (true);

-- 4. Kontrol
SELECT '✅ product_views RLS policy düzeltildi!' AS durum;

-- Policy'leri kontrol et
SELECT 
  policyname, 
  cmd, 
  permissive, 
  roles,
  CASE 
    WHEN qual IS NOT NULL THEN 'USING: ' || substring(qual::text, 1, 50)
    WHEN with_check IS NOT NULL THEN 'WITH CHECK: ' || substring(with_check::text, 1, 50)
    ELSE 'No condition'
  END AS condition
FROM pg_policies
WHERE tablename = 'product_views';

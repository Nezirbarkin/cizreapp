-- ============================================================================
-- product_views RLS POLICY FIX
-- ============================================================================
-- Hata: new row violates row-level security policy for table "product_views"
-- Kullanıcılar ürün görüntülediklerinde product_views tablosuna INSERT yapamıyor
-- ============================================================================

-- 1. Mevcut policy'leri kontrol et
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'product_views';

-- 2. INSERT policy ekle (authenticated kullanıcılar kendi view'larını ekleyebilir)
DROP POLICY IF EXISTS "Users can insert their own product views" ON product_views;
CREATE POLICY "Users can insert their own product views"
ON product_views
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- 3. Anonim kullanıcılar da view ekleyebilsin (opsiyonel - guest mode için)
DROP POLICY IF EXISTS "Anyone can insert product views" ON product_views;
CREATE POLICY "Anyone can insert product views"
ON product_views
FOR INSERT
TO authenticated, anon
WITH CHECK (true);

-- 4. SELECT policy (istatistikler için)
DROP POLICY IF EXISTS "Users can view product views" ON product_views;
CREATE POLICY "Users can view product views"
ON product_views
FOR SELECT
TO authenticated
USING (true);

SELECT 'product_views RLS policy düzeltildi!' AS durum;

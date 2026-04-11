-- ============================================================================
-- product_views RLS TEMİZLİK - ESKİ POLICY'İ KALDIR
-- ============================================================================

-- Eski policy'yi kaldır (hala mevcut)
DROP POLICY IF EXISTS "product_views_select_owner_or_admin" ON product_views;

SELECT '✅ Eski product_views policy kaldırıldı!' AS durum;

-- Tüm policy'leri kontrol et
SELECT policyname, cmd, permissive, roles
FROM pg_policies
WHERE tablename = 'product_views';

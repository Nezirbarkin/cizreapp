-- ============================================================================
-- FIX: Shops permission denied for table users error
-- ============================================================================
-- Hata: PostgrestException(message: permission denied for table users, code: 42501)
-- Çözüm: Shops RLS policy'lerini düzelt ve güvenlik tanımlı fonksiyonlar kullan

-- 1. Mevcut TÜM shops policy'lerini temizle (eski ve yeni)
DROP POLICY IF EXISTS "shops_select_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_insert_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_update_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_delete_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_select_own" ON public.shops;
DROP POLICY IF EXISTS "shops_admin_select_all" ON public.shops;
DROP POLICY IF EXISTS "shops_admin_update" ON public.shops;
DROP POLICY IF EXISTS "shops_select_anon_unified" ON public.shops;
DROP POLICY IF EXISTS "shops_select_authenticated_unified" ON public.shops;
DROP POLICY IF EXISTS "shops_delete_authenticated_unified" ON public.shops;
DROP POLICY IF EXISTS "shops_update_authenticated_unified" ON public.shops;

-- Not: shops_select_own ve shops_admin_update artık ayrı policy değil,
-- shops_select_policy ve shops_update_policy içinde birleştirildi

-- 2. SELECT Policy - BİRLEŞTİRİLMİŞ (public + authenticated + owner)
-- Onaylanmış dükkanlar herkes görür, sahipler kendi dükkanlarını her zaman görür
CREATE POLICY "shops_select_policy"
ON public.shops
FOR SELECT
TO public, authenticated
USING (
    -- Onaylanmış aktif dükkanlar herkes görebilir
    (is_active = true AND is_approved = true)
    OR
    -- Dükkan sahipleri kendi dükkanlarını her zaman görebilir
    (owner_id = (select auth.uid()))
);

-- 4. INSERT Policy - Satıcılar dükkan oluşturabilir
CREATE POLICY "shops_insert_policy"
ON public.shops
FOR INSERT
TO authenticated
WITH CHECK (
    owner_id = (select auth.uid())
);

-- 5. UPDATE Policy - BİRLEŞTİRİLMİŞ (owner + admin)
-- Dükkan sahibi veya admin güncelleyebilir
CREATE POLICY "shops_update_policy"
ON public.shops
FOR UPDATE
TO authenticated
USING (
    owner_id = (select auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM profiles
        WHERE id = (select auth.uid())
        AND is_admin = true
    )
)
WITH CHECK (
    owner_id = (select auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM profiles
        WHERE id = (select auth.uid())
        AND is_admin = true
    )
);

-- 7. DELETE Policy - Adminler silebilir
CREATE POLICY "shops_delete_policy"
ON public.shops
FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles
        WHERE id = (select auth.uid())
        AND is_admin = true
    )
);

-- 8. shops_with_products_stats view'ını kontrol et ve yeniden oluştur
DROP VIEW IF EXISTS shops_with_products_stats;

CREATE VIEW shops_with_products_stats
WITH (security_invoker = on) AS
SELECT
  s.id,
  s.name,
  s.description,
  s.logo_url,
  s.banner_url,
  s.category_id,
  s.owner_id,
  s.address,
  s.phone,
  s.is_active,
  s.is_approved,
  s.is_verified,
  s.is_pinned,
  s.rating,
  s.review_count,
  s.delivery_fee,
  s.min_order_amount,
  s.free_delivery_min_amount,
  s.delivery_time,
  s.is_open,
  s.created_at,
  s.updated_at,
  COALESCE(pc.product_count, 0) as products_count,
  CASE
    WHEN s.is_active = true AND s.is_approved = true THEN true
    ELSE false
  END as is_listable
FROM shops s
LEFT JOIN (
  SELECT shop_id, COUNT(*) as product_count
  FROM products
  WHERE is_active = true
  GROUP BY shop_id
) pc ON s.id = pc.shop_id
WHERE s.is_active = true;

-- 9. Gerekli index'ler
CREATE INDEX IF NOT EXISTS idx_shops_active_approved ON public.shops(is_active, is_approved);
CREATE INDEX IF NOT EXISTS idx_shops_category ON public.shops(category_id) WHERE is_active = true AND is_approved = true;
CREATE INDEX IF NOT EXISTS idx_shops_owner_id ON public.shops(owner_id);

-- 10. Kontrol
DO $$
BEGIN
    RAISE NOTICE '✅ Shops permissions fixed!';
    RAISE NOTICE '✅ shops_with_products_stats view recreated!';
END $$;

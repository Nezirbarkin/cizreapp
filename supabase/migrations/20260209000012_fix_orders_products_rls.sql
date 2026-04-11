-- Fix Orders and Products RLS INSERT Policies
-- Bu migration, orders ve products tablolarının INSERT politikalarını düzeltir

-- ============================================================================
-- ORDERS TABLOSU RLS POLICY DÜZELTMELERİ
-- ============================================================================

-- Mevcut policy'leri temizle
DROP POLICY IF EXISTS "orders_insert_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_unified" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_own_orders" ON public.orders;
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_select_own_orders" ON public.orders;
DROP POLICY IF EXISTS "orders_select_all_for_admins" ON public.orders;
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_update_own_orders" ON public.orders;
DROP POLICY IF EXISTS "orders_update_status" ON public.orders;
DROP POLICY IF EXISTS "orders_delete_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_delete_own_orders" ON public.orders;

-- INSERT Policy - Kullanıcı kendi siparişini oluşturabilir
CREATE POLICY "orders_insert_policy" 
ON public.orders 
FOR INSERT 
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- SELECT Policy - Kullanıcı kendi siparişlerini, satıcı kendi dükkanının siparişlerini, admin tümünü görebilir
CREATE POLICY "orders_select_policy" 
ON public.orders 
FOR SELECT 
TO authenticated
USING (
  auth.uid() = user_id
  OR shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid())
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
);

-- UPDATE Policy - Admin ve siparişin sahibi güncelleyebilir (status değişikliği için)
CREATE POLICY "orders_update_policy" 
ON public.orders 
FOR UPDATE 
TO authenticated
USING (
  auth.uid() = user_id
  OR shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid())
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
)
WITH CHECK (
  auth.uid() = user_id
  OR shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid())
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
);

-- DELETE Policy - Sadece admin silebilir
CREATE POLICY "orders_delete_policy" 
ON public.orders 
FOR DELETE 
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================================================
-- PRODUCTS TABLOSU RLS POLICY DÜZELTMELERİ
-- ============================================================================

-- Mevcut policy'leri temizle
DROP POLICY IF EXISTS "products_select_policy" ON public.products;
DROP POLICY IF EXISTS "products_insert_policy" ON public.products;
DROP POLICY IF EXISTS "products_update_policy" ON public.products;
DROP POLICY IF EXISTS "products_delete_policy" ON public.products;
DROP POLICY IF EXISTS "products_update_own_products" ON public.products;
DROP POLICY IF EXISTS "products_delete_own_products" ON public.products;

-- SELECT Policy - Aktif ürünler herkes tarafından görülebilir
CREATE POLICY "products_select_policy" 
ON public.products 
FOR SELECT 
TO authenticated
USING (is_active = true);

-- INSERT Policy - Satıcılar kendi dükkanları için ürün ekleyebilir
CREATE POLICY "products_insert_policy" 
ON public.products 
FOR INSERT 
TO authenticated
WITH CHECK (
  shop_id IN (
    SELECT id FROM shops 
    WHERE owner_id = auth.uid()
  )
);

-- UPDATE Policy - Ürün sahibi güncelleyebilir
CREATE POLICY "products_update_policy" 
ON public.products 
FOR UPDATE 
TO authenticated
USING (
  shop_id IN (
    SELECT id FROM shops 
    WHERE owner_id = auth.uid()
  )
)
WITH CHECK (
  shop_id IN (
    SELECT id FROM shops 
    WHERE owner_id = auth.uid()
  )
);

-- DELETE Policy - Ürün sahibi silebilir
CREATE POLICY "products_delete_policy" 
ON public.products 
FOR DELETE 
TO authenticated
USING (
  shop_id IN (
    SELECT id FROM shops 
    WHERE owner_id = auth.uid()
  )
);

-- ============================================================================
-- SHOPS TABLOSU RLS POLICY DÜZELTMELERİ
-- ============================================================================

-- Mevcut policy'leri temizle
DROP POLICY IF EXISTS "shops_select_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_insert_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_update_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_delete_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_insert_own_shop" ON public.shops;
DROP POLICY IF EXISTS "shops_update_own_shop" ON public.shops;

-- SELECT Policy - Onaylanmış dükkanlar herkes tarafından görülebilir
CREATE POLICY "shops_select_policy"
ON public.shops
FOR SELECT
TO authenticated
USING (is_approved = true OR owner_id = auth.uid() OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- INSERT Policy - Satıcılar dükkan oluşturabilir (owner_id = auth.uid() olmalı)
CREATE POLICY "shops_insert_policy"
ON public.shops
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = owner_id
  AND EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'seller')
);

-- UPDATE Policy - Dükkan sahibi güncelleyebilir
CREATE POLICY "shops_update_policy"
ON public.shops
FOR UPDATE
TO authenticated
USING (
  owner_id = auth.uid()
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
)
WITH CHECK (
  owner_id = auth.uid()
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
);

-- DELETE Policy - Sadece admin silebilir
CREATE POLICY "shops_delete_policy"
ON public.shops
FOR DELETE
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================================================
-- RLS Aktif Olduğundan Emin Ol
-- ============================================================================

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;

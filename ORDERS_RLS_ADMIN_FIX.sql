-- ============================================================================
-- Admin için Orders RLS Politikaları
-- ============================================================================
-- Bu script admin kullanıcılarının tüm siparişleri görmesine izin verir
-- ============================================================================

-- Önce mevcut politikaları kaldır
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "Admin can view all orders" ON public.orders;
DROP POLICY IF EXISTS "Users can view own orders" ON public.orders;
DROP POLICY IF EXISTS "Shop owners can view their shop orders" ON public.orders;

-- Yeni politika: Admin tüm siparişleri görebilir, kullanıcılar kendi siparişlerini
CREATE POLICY "orders_select_policy" ON public.orders 
FOR SELECT TO authenticated 
USING (
  -- Admin her şeyi görebilir
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
  OR
  -- Kullanıcı kendi siparişlerini görebilir
  user_id = auth.uid()
  OR
  -- Satıcı kendi dükkanının siparişlerini görebilir
  EXISTS (
    SELECT 1 FROM public.shops 
    WHERE shops.id = orders.shop_id 
    AND shops.owner_id = auth.uid()
  )
);

-- Güncelleme politikası
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;
CREATE POLICY "orders_update_policy" ON public.orders 
FOR UPDATE TO authenticated 
USING (
  -- Admin güncelleme yapabilir
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
  OR
  -- Satıcı kendi siparişlerini güncelleyebilir
  EXISTS (
    SELECT 1 FROM public.shops 
    WHERE shops.id = orders.shop_id 
    AND shops.owner_id = auth.uid()
  )
);

-- Silme politikası (sadece admin)
DROP POLICY IF EXISTS "orders_delete_policy" ON public.orders;
DROP POLICY IF EXISTS "Admin can delete orders" ON public.orders;
CREATE POLICY "orders_delete_policy" ON public.orders 
FOR DELETE TO authenticated 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
);

-- Insert politikası (kullanıcılar sipariş verebilir)
DROP POLICY IF EXISTS "orders_insert_policy" ON public.orders;
DROP POLICY IF EXISTS "Users can create orders" ON public.orders;
CREATE POLICY "orders_insert_policy" ON public.orders 
FOR INSERT TO authenticated 
WITH CHECK (user_id = auth.uid());

-- Politikaları doğrula
SELECT tablename, policyname, cmd, roles, qual 
FROM pg_policies 
WHERE tablename = 'orders';

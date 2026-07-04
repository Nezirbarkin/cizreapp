-- =============================================================================
-- 20260701_COURIER_RLS_ROLLBACK.sql
-- Acil kurtarma: V2'nin 42501 "permission denied for function is_admin"
-- hatasını çözmek için V2 helper function ve policy'leri geri al.
-- V1 de recursion'a yol açtığı için V1 de geri alınıyor.
-- Sonuç: orders_select_policy / orders_update_policy orijinal (user_id OR shop owner OR admin)
-- 3 koşuluna döner. Kurye "Teslim Ettim" → sipariş kaybolma SORUNU henüz çözülmez,
-- ama uygulama çalışır hâle gelir.
-- =============================================================================

-- Helper function'ı sil (V2'den). CASCADE gerekli çünkü orders policy'leri
-- bu fonksiyona bağımlı; CASCADE bağımlı policy'leri de düşürür (zaten
-- aşağıda yeniden oluşturuyoruz).
DROP FUNCTION IF EXISTS public.courier_assigned_to_order(uuid) CASCADE;

-- V2 ile yarım kalmış policy'leri temizle
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;

-- Orijinal 3 koşullu policy'leri geri kur (V1 öncesi hâli)
CREATE POLICY "orders_select_policy"
  ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR
    EXISTS (
      SELECT 1 FROM public.shops
      WHERE shops.id = orders.shop_id
        AND shops.owner_id = (SELECT auth.uid())
    )
    OR
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
        AND profiles.role = 'admin'
    )
  );

CREATE POLICY "orders_update_policy"
  ON public.orders
  FOR UPDATE
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR
    EXISTS (
      SELECT 1 FROM public.shops
      WHERE shops.id = orders.shop_id
        AND shops.owner_id = (SELECT auth.uid())
    )
    OR
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
        AND profiles.role = 'admin'
    )
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    OR
    EXISTS (
      SELECT 1 FROM public.shops
      WHERE shops.id = orders.shop_id
        AND shops.owner_id = (SELECT auth.uid())
    )
    OR
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
        AND profiles.role = 'admin'
    )
  );

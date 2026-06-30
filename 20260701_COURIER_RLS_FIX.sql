-- =============================================================================
-- 20260701_COURIER_RLS_FIX.sql
-- Sorun: Kurye, kendisine atanmış delivered/on_the_way/picked_up siparişlerin
-- orders satırını göremiyor (RLS kapsamı dışında). Bu yüzden kurye panelinde
-- "Teslim Ettim" sonrası sipariş anlık görünmez oluyor; ayrıca delivered sonrası
-- delivered_courier_id/name/phone alanları da kurye oturumundan yazılamıyor.
--
-- Düzeltme:
--   orders_select_policy  → kurye kendi atanmış siparişini görebilir
--   orders_update_policy  → kurye kendi atanmış siparişini güncelleyebilir
-- =============================================================================

-- 1) orders_select_policy'yi yeniden oluştur (idempotent)
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;

CREATE POLICY "orders_select_policy"
  ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    -- Müşteri kendi siparişini görür
    user_id = (SELECT auth.uid())
    OR
    -- Satıcı kendi mağazasına ait siparişleri görür
    EXISTS (
      SELECT 1 FROM public.shops
      WHERE shops.id = orders.shop_id
        AND shops.owner_id = (SELECT auth.uid())
    )
    OR
    -- Admin tüm siparişleri görür
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
        AND profiles.role = 'admin'
    )
    OR
    -- Kurye kendisine atanmış siparişleri görür (delivered dahil tüm durumlar)
    EXISTS (
      SELECT 1 FROM public.courier_assignments ca
      WHERE ca.order_id = orders.id
        AND ca.courier_id = (SELECT auth.uid())
    )
  );

-- 2) orders_update_policy'yi yeniden oluştur
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;

CREATE POLICY "orders_update_policy"
  ON public.orders
  FOR UPDATE
  TO authenticated
  USING (
    -- Müşteri kendi siparişini günceller (örn. iptal)
    user_id = (SELECT auth.uid())
    OR
    -- Satıcı kendi mağazasına ait siparişi günceller
    EXISTS (
      SELECT 1 FROM public.shops
      WHERE shops.id = orders.shop_id
        AND shops.owner_id = (SELECT auth.uid())
    )
    OR
    -- Admin her siparişi güncelleyebilir
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
        AND profiles.role = 'admin'
    )
    OR
    -- Kurye kendisine atanmış siparişin durumunu güncelleyebilir
    -- (picked_up / on_the_way / delivered). delivered_courier_* alanlarını
    -- da kurye yazabilsin.
    EXISTS (
      SELECT 1 FROM public.courier_assignments ca
      WHERE ca.order_id = orders.id
        AND ca.courier_id = (SELECT auth.uid())
    )
  )
  WITH CHECK (
    -- Yazma sonrası koşul da aynı owner mantığı ile
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
    OR
    EXISTS (
      SELECT 1 FROM public.courier_assignments ca
      WHERE ca.order_id = orders.id
        AND ca.courier_id = (SELECT auth.uid())
    )
  );

-- =============================================================================
-- Doğrulama (çalıştırıldıktan sonra okunur)
-- =============================================================================
SELECT policyname, cmd, LEFT(qual::text, 80) || '...' AS qual_preview
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'orders'
ORDER BY cmd, policyname;

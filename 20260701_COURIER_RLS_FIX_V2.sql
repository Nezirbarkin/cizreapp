-- =============================================================================
-- 20260701_COURIER_RLS_FIX_V2.sql
-- V1'de ortaya çıkan 42P17 infinite recursion hatası düzeltmesi.
--
-- Sebep: orders_select_policy içinde `EXISTS (SELECT ... FROM courier_assignments ...)`
-- kullanıldı. courier_assignments tablosunun da orders'a bakan bir SELECT policy'si
-- var ("Sellers can view order assignments"). İki policy birbirine SELECT ile
-- bağımlı olunca Postgres policy expansion sırasında sonsuz recursion tespit
-- ediyor (PostgreSQL "infinite recursion detected in policy for relation orders").
--
-- Düzeltme: orders policy içindeki courier_assignments erişimi
-- SECURITY DEFINER bir helper fonksiyon üzerinden yapılır. SECURITY DEFINER
-- fonksiyon içinde RLS uygulanmaz, dolayısıyla courier_assignments policy'si
-- tetiklenmez ve recursion oluşmaz.
--
-- Mevcut bozuk policy'ler önce düşürülür (DROP IF EXISTS ile idempotent),
-- sonra helper function + düzeltilmiş policy'ler oluşturulur.
-- =============================================================================

-- 0) V1 sonrası yarım kalmış / recursion'a sebep olan policy'leri temizle
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;

-- 1) Helper function: kurye bu siparişe atanmış mı?
-- SECURITY DEFINER: RLS'yi bypass eder → courier_assignments policy'si tetiklenmez.
-- STABLE: aynı input için aynı transaction içinde sonuç değişmez (optimizer caching).
CREATE OR REPLACE FUNCTION public.courier_assigned_to_order(p_order_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.courier_assignments ca
    WHERE ca.order_id = p_order_id
      AND ca.courier_id = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.courier_assigned_to_order(uuid) TO authenticated;

-- 2) orders SELECT policy — kurye koşulu SECURITY DEFINER fn ile
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
    -- Kurye kendisine atanmış siparişleri görür (RLS recursion yok)
    public.courier_assigned_to_order(orders.id)
  );

-- 3) orders UPDATE policy
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
    OR
    public.courier_assigned_to_order(orders.id)
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
    OR
    public.courier_assigned_to_order(orders.id)
  );

-- =============================================================================
-- Doğrulama
-- =============================================================================
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'orders'
ORDER BY cmd, policyname;

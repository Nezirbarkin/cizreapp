-- =============================================================================
-- 20260701_COURIER_RLS_FIX_V3.sql
-- V1 (infinite recursion) ve V2 (permission denied for function is_admin)
-- hatalarının kesin çözümü: denormalize kolon yaklaşımı.
--
-- Neden V1/V2 başarısız:
--   V1: orders policy içinde `EXISTS (SELECT ... FROM courier_assignments ...)`
--       yazıldı; courier_assignments SELECT policy'si içinde de orders'a
--       bakan bir koşul vardı (Sellers can view order assignments). Postgres
--       policy expansion sırasında 42P17 infinite recursion fırlattı.
--   V2: SECURITY DEFINER helper function postgres rolüne düşerek
--       auth.uid() → ... → is_admin çağrısında 42501 permission denied.
--
-- V3 çözümü (subquery'siz, RLS bağımsız):
--   1. orders tablosuna assigned_courier_id UUID kolonu eklenir
--   2. courier_assignments INSERT/UPDATE trigger fonksiyonu orders.assigned_courier_id
--      kolonunu otomatik senkronize eder (assignment oluşunca order.id ↔ courier_id)
--   3. orders_select_policy ve orders_update_policy'ye
--      `OR assigned_courier_id = (SELECT auth.uid())` eklenir.
--      Bu basit bir kolon karşılaştırmasıdır, subquery yok, RLS tetiklemez,
--      recursion oluşturmaz, permission hatası vermez.
--   4. Teslim edilen atamalar için (status='delivered') courier_assignments
--      trigger'ı orders.assigned_courier_id'yi NULL yapmaz (kurye geçmiş
--      siparişlerini görmeye devam eder). Kurye paneli delivered siparişi
--      "Siparişlerim" sekmesinde listelemeye devam eder.
--
-- V3 PREREQUISITE:
--   Önce V2'yi geri alın: 20260701_COURIER_RLS_ROLLBACK.sql çalıştırılmalı.
-- =============================================================================

-- 1) Denormalize kolon: orders tablosuna assigned_courier_id
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS assigned_courier_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_orders_assigned_courier
  ON public.orders(assigned_courier_id)
  WHERE assigned_courier_id IS NOT NULL;

-- 2) courier_assignments INSERT/UPDATE → orders.assigned_courier_id senkronizasyonu
-- Trigger fonksiyonu: bir order'a birden fazla courier_assignment varsa (pickup atandı
-- sonra iptal edildi vb.) en son assigned olan kurye kazanır. delivered sonrası da
-- atanmış kurye kalır (kurye geçmişi görmeye devam eder).
CREATE OR REPLACE FUNCTION public.sync_assigned_courier_to_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    UPDATE public.orders
    SET assigned_courier_id = NEW.courier_id,
        updated_at = NOW()
    WHERE id = NEW.order_id;
    RETURN NEW;
  ELSIF (TG_OP = 'UPDATE') THEN
    UPDATE public.orders
    SET assigned_courier_id = NEW.courier_id,
        updated_at = NOW()
    WHERE id = NEW.order_id;
    RETURN NEW;
  ELSIF (TG_OP = 'DELETE') THEN
    -- Yalnızca silinen assignment o siparişe bağlı son atama ise NULL yap
    UPDATE public.orders
    SET assigned_courier_id = NULL,
        updated_at = NOW()
    WHERE id = OLD.order_id
      AND assigned_courier_id = OLD.courier_id
      AND NOT EXISTS (
        SELECT 1 FROM public.courier_assignments ca
        WHERE ca.order_id = OLD.order_id
      );
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trigger_sync_assigned_courier ON public.courier_assignments;
CREATE TRIGGER trigger_sync_assigned_courier
  AFTER INSERT OR UPDATE OR DELETE ON public.courier_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_assigned_courier_to_order();

-- 3) Mevcut verileri geriye dönük doldur (backfill)
-- Her sipariş için en son INSERT edilen courier_assignment'ın courier_id'sini ata.
UPDATE public.orders o
SET assigned_courier_id = ca.courier_id
FROM (
  SELECT DISTINCT ON (order_id) order_id, courier_id
  FROM public.courier_assignments
  ORDER BY order_id, created_at DESC
) ca
WHERE ca.order_id = o.id
  AND o.assigned_courier_id IS NULL;

-- 4) orders SELECT policy — kurye koşulu subquery'siz
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
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
    OR
    -- Kurye kendisine atanmış siparişleri görür (basit kolon karşılaştırması)
    assigned_courier_id = (SELECT auth.uid())
  );

-- 5) orders UPDATE policy — kurye teslim/aldım güncelleyebilir
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;
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
    -- Kurye kendi atanmış siparişini günceller (status, delivered_courier_*)
    assigned_courier_id = (SELECT auth.uid())
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
    assigned_courier_id = (SELECT auth.uid())
  );

-- =============================================================================
-- Doğrulama
-- =============================================================================
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'orders'
ORDER BY cmd, policyname;

-- Backfill örneklem: son 5 teslim edilmiş siparişin assigned_courier_id'si
SELECT o.id AS order_id, o.status, o.assigned_courier_id,
       p.full_name AS courier_name
FROM orders o
LEFT JOIN profiles p ON p.id = o.assigned_courier_id
WHERE o.status = 'delivered'
ORDER BY o.delivered_at DESC NULLS LAST
LIMIT 5;

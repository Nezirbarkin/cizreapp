-- =============================================================================
-- 20260701_COURIER_RLS_FIX_V3_2.sql
-- V3'ün güvenli son sürümü. V1 (recursion) + V2 (is_admin 42501) hatalarını
-- tamamen bypass eder.
--
-- TEMEL PRENSİPLER (PROJE_HAVIZA'dan öğrenilenler):
--  1. orders policy içinde courier_assignments'a subquery YAPMA → recursion
--  2. SECURITY DEFINER fn içinde auth.uid() çağırma → is_admin zinciri → 42501
--  3. policy içinde is_admin()/auth_is_admin() helper çağırma → profiles bağımlılığı
--
-- V3_2 ÇÖZÜMÜ:
--  - orders tablosuna assigned_courier_id UUID kolonu ekle (denormalize)
--  - sync_assigned_courier_to_order() trigger fn: SECURITY INVOKER, auth.uid() YOK
--    (sadece NEW.courier_id / OLD.courier_id kolonlarını orders'a kopyalar)
--    NOT: SECURITY INVOKER olduğu için courier_assignments INSERT/UPDATE yapan
--    kullanıcının orders tablosunda UPDATE izni olmalı — bunu orders_update_policy
--    zaten (kurye için assigned_courier_id koşuluyla) sağlıyor. Ama yeni INSERT
--    anında orders.assigned_courier_id henüz NULL, yani kurye koşulu tutmaz.
--    Bu yüzden trigger fn SECURITY DEFINER yapıp auth.uid() KULLANMADAN sadece
--    UPDATE yapan minimal bir fn olacak — auth.uid()'ye bağımlı olmadığı için
--    is_admin zincirine düşmez, 42501 vermez.
--  - orders SELECT/UPDATE policy: kurye koşulu `assigned_courier_id = auth.uid()`
--    (basit kolon karşılaştırması, subquery yok, recursion yok)
--  - Admin koşulu: `EXISTS(SELECT 1 FROM profiles WHERE id=(SELECT auth.uid())
--    AND role='admin')` — FIX_ORDERS_POLICIES_CLEAN.sql pattern'i, helper fn yok.
--
-- PREREQUISITE: V2 rollback yapılmış olmalı (20260701_COURIER_RLS_ROLLBACK.sql).
-- =============================================================================

-- 1) Denormalize kolon
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS assigned_courier_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_orders_assigned_courier
  ON public.orders(assigned_courier_id)
  WHERE assigned_courier_id IS NOT NULL;

-- 2) Senkronizasyon trigger fonksiyonu
-- SECURITY DEFINER ama auth.uid() KULLANMIYOR → is_admin/auth_is_admin zinciri yok
-- → 42501 riski yok. Sadece NEW/OLD kolonlarını orders'a kopyalar.
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

GRANT EXECUTE ON FUNCTION public.sync_assigned_courier_to_order() TO authenticated, service_role, anon;

DROP TRIGGER IF EXISTS trigger_sync_assigned_courier ON public.courier_assignments;
CREATE TRIGGER trigger_sync_assigned_courier
  AFTER INSERT OR UPDATE OR DELETE ON public.courier_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_assigned_courier_to_order();

-- 3) Backfill: mevcut atamaları doldur
UPDATE public.orders o
SET assigned_courier_id = sub.courier_id
FROM (
  SELECT DISTINCT ON (order_id) order_id, courier_id
  FROM public.courier_assignments
  ORDER BY order_id, created_at DESC
) sub
WHERE sub.order_id = o.id
  AND o.assigned_courier_id IS NULL;

-- 4) orders SELECT policy — kurye koşulu basit kolon karşılaştırması
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
    -- Admin: DOĞRUDAN profiles.role subquery (is_admin()/auth_is_admin() yok)
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = (SELECT auth.uid())
        AND profiles.role = 'admin'
    )
    OR
    -- Kurye kendisine atanmış siparişleri görür (kolon karşılaştırması)
    assigned_courier_id = (SELECT auth.uid())
  );

-- 5) orders UPDATE policy
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

SELECT o.id AS order_id, o.status, o.assigned_courier_id,
       p.full_name AS courier_name
FROM orders o
LEFT JOIN profiles p ON p.id = o.assigned_courier_id
WHERE o.status = 'delivered'
ORDER BY o.delivered_at DESC NULLS LAST
LIMIT 5;
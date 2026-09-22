-- =============================================================================
-- orders SELECT — KURYE HAVUZU DALINI KURYELERE DARALT
-- -----------------------------------------------------------------------------
-- Bu, realtime yayını düzeltmesinin (20260917000003) ÖN KOŞULUDUR ama tek
-- başına da bir güvenlik düzeltmesidir.
--
-- ## Bulunan açık
--
-- `orders_select_merged` politikasının İLK dalı auth.uid()'ye hiç bakmıyordu:
--
--     (EXISTS (SELECT 1 FROM shops s
--               WHERE s.id = orders.shop_id
--                 AND (s.has_own_courier IS NULL OR s.has_own_courier = false)))
--     AND status = ANY (ARRAY['confirmed','preparing','ready'])
--
-- Yani kuryesi olmayan bir satıcının HAZIRLANMAKTA olan her siparişini
-- HERHANGİ bir oturum açmış kullanıcı okuyabiliyordu — satırda
-- `delivery_address_text`, `customer_phone`, `delivery_notes` var.
-- Canlıda ölçüldü (BEGIN/ROLLBACK içinde bir sipariş geçici olarak
-- 'confirmed' yapılıp `SET LOCAL ROLE authenticated` ile bakıldı):
-- hiç siparişi olmayan, kurye/satıcı/admin olmayan sıradan bir müşteri
-- profili o siparişi GÖRÜYORDU.
--
-- ## Neden bu dal gereksiz
--
-- Kurye havuzu uygulamada bu tablodan okunmuyor: kurye paneli
-- `get_available_orders_for_courier()` RPC'sini çağırıyor (bkz.
-- 20260811000001) — SECURITY DEFINER, `is_courier_role()` ile kapılı ve
-- PII DÖNDÜRMÜYOR (yalnızca tutar, dükkân, kalem sayısı). Adres/telefon
-- ancak siparişi kabul eden kuryeye `get_courier_active_orders()` ile
-- açılıyor. Yani bu dal, RPC'ler yazılmadan önceki dönemden kalmış bir
-- artık (bkz. `_select_merged` birleştirmeleri).
--
-- ## Yapılan
--
-- Dal SİLİNMEDİ, `is_courier_role()` ile kapıya alındı: bir kurye istemcisi
-- havuzu doğrudan tablodan okumaya kalkarsa davranış bozulmaz, ama sıradan
-- kullanıcıya kapanır. Politikanın diğer dalları (kendi siparişim, dükkân
-- sahibi, atanmış kurye, admin) AYNEN korunur — birleştirmeden gelen
-- yinelenen dallar sadeleştirildi, kapsam değişmedi.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

DROP POLICY IF EXISTS orders_select_merged ON public.orders;

CREATE POLICY orders_select_merged ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    -- Siparişi veren müşteri
    user_id = (SELECT auth.uid())
    -- Siparişe atanmış kurye
    OR assigned_courier_id = (SELECT auth.uid())
    -- Siparişin dükkân sahibi
    OR EXISTS (
      SELECT 1 FROM public.shops AS s
      WHERE s.id = orders.shop_id AND s.owner_id = (SELECT auth.uid())
    )
    -- Admin
    OR EXISTS (
      SELECT 1 FROM public.profiles AS p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'admin'::public.user_role
    )
    -- KURYE HAVUZU: yalnızca kurye rolündekiler, yalnızca kuryesi olmayan
    -- dükkânların hazırlanan siparişleri.
    OR (
      public.is_courier_role()
      AND status = ANY (ARRAY['confirmed','preparing','ready']::public.order_status[])
      AND EXISTS (
        SELECT 1 FROM public.shops AS s
        WHERE s.id = orders.shop_id
          AND COALESCE(s.has_own_courier, false) = false
      )
    )
  );

COMMENT ON POLICY orders_select_merged ON public.orders IS
  'Siparişi: müşterisi, dükkân sahibi, atanmış kuryesi ve admin görür. Kurye havuzu dalı is_courier_role() ile kapılıdır (PII''li satırlar sıradan kullanıcıya açılmaz); havuzun asıl kaynağı get_available_orders_for_courier() RPC''sidir.';

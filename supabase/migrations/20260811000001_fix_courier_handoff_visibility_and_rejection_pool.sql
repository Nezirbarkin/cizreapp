-- ============================================================================
-- Kurye sipariş devri görünürlüğü ve reddedilen sipariş havuzu düzeltmesi
-- ----------------------------------------------------------------------------
-- reject_order_assignment mevcut assignment satırını yeni kuryeye devreder.
-- Yeni kurye bu satırı get_courier_active_orders() ile güvenli biçimde okur.
--
-- Bir sonraki kurye bulunamazsa assignment cancelled, order ready olur. Önceki
-- get_available_orders_for_courier() reddetme tablosunu kontrol etmediği için
-- siparişi reddeden kurye aynı siparişi yeniden havuzda görüp tekrar alabiliyordu.
-- Bu migration havuzu kurye bazında filtreler; PII dönüş sözleşmesini değiştirmez.
-- ============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS public.get_available_orders_for_courier();

CREATE FUNCTION public.get_available_orders_for_courier()
RETURNS TABLE(
  id uuid,
  total numeric,
  shop_id uuid,
  shop_name text,
  created_at timestamptz,
  item_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    o.id,
    o.total,
    o.shop_id,
    s.name,
    o.created_at,
    (
      SELECT count(*)
      FROM public.order_items AS oi
      WHERE oi.order_id = o.id
    ) AS item_count
  FROM public.orders AS o
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE o.status IN ('confirmed', 'preparing', 'ready')
    AND COALESCE(s.has_own_courier, false) = false
    AND (SELECT auth.uid()) IS NOT NULL
    AND public.is_courier_role()
    AND o.user_id IS DISTINCT FROM (SELECT auth.uid())
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_assignments AS ca
      WHERE ca.order_id = o.id
        AND ca.status IN ('assigned', 'picked_up', 'on_the_way', 'delivered')
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_order_rejections AS cor
      WHERE cor.order_id = o.id
        AND cor.courier_id = (SELECT auth.uid())
    )
  ORDER BY o.created_at ASC;
$$;

REVOKE ALL ON FUNCTION public.get_available_orders_for_courier()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_available_orders_for_courier()
  TO authenticated;

COMMENT ON FUNCTION public.get_available_orders_for_courier() IS
  'Kurye için PII içermeyen sipariş havuzu. Kuryesi olmayan satıcı siparişlerini döndürür; aktif/teslim edilmiş ataması olan, kuryenin kendi verdiği veya daha önce reddettiği siparişleri dışlar.';

-- Devirden sonra yeni kurye aynı assignment satırını görür; tam PII yalnızca
-- assignment sahibi kurye veya admin için döner. Mevcut fonksiyonun güvenlik
-- sözleşmesini yeniden kurarak migration drift'ine karşı deterministik yap.
DROP FUNCTION IF EXISTS public.get_courier_active_orders();

CREATE FUNCTION public.get_courier_active_orders()
RETURNS TABLE(
  assignment_id uuid,
  assignment_status text,
  fee_amount numeric,
  assigned_at timestamptz,
  order_id uuid,
  order_total numeric,
  order_status text,
  delivery_address_text text,
  customer_phone text,
  created_at timestamptz,
  shop_name text,
  order_items_json jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_courier_role() AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | kurye veya admin gerekli'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    ca.id::uuid,
    ca.status::text,
    ca.fee_amount::numeric,
    ca.assigned_at::timestamptz,
    o.id::uuid,
    o.total::numeric,
    o.status::text,
    o.delivery_address_text::text,
    o.customer_phone::text,
    o.created_at::timestamptz,
    s.name::text,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'quantity', oi.quantity,
            'product_name', oi.product_name
        )
          ORDER BY oi.product_name, oi.quantity
        )
        FROM public.order_items AS oi
        WHERE oi.order_id = o.id
      ),
      '[]'::jsonb
    )
  FROM public.courier_assignments AS ca
  JOIN public.orders AS o ON o.id = ca.order_id
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE (ca.courier_id = v_uid OR public.is_admin())
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
  ORDER BY ca.assigned_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_active_orders()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_active_orders()
  TO authenticated;

COMMENT ON FUNCTION public.get_courier_active_orders() IS
  'Atama sahibi kurye veya admin için aktif siparişleri tam teslimat detayıyla döndürür. courier_id devrinde aynı assignment yeni kuryeye görünür.';

NOTIFY pgrst, 'reload schema';


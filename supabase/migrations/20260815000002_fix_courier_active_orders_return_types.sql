-- ============================================================================
-- get_courier_active_orders 42804 dönüş tipi düzeltmesi
-- ----------------------------------------------------------------------------
-- Canlı courier_assignments.fee_amount kolonu double precision iken RPC'nin
-- RETURNS TABLE sözleşmesi numeric bekliyordu. PostgreSQL RETURN QUERY sırasında
-- örtük dönüşüm yapmadığı için tüm aktif sipariş sorgusu 42804 ile düşüyordu.
-- orders.total ve shop adı da şema drift'ine karşı açıkça sözleşme tipine cast
-- edilir. Böylece atama mevcut olduğunda kurye paneli siparişi okuyabilir.
-- ============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- Kullanılmayan eski overload PII içerir ve PostgREST sözleşmesini gereksiz yere
-- çoğaltır. Varsa kaldır.
DROP FUNCTION IF EXISTS public.get_courier_active_orders(uuid);
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
    )::jsonb
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
  'Atama sahibi kurye veya admin için aktif siparişleri döndürür. Tüm RETURN QUERY kolonları RETURNS TABLE sözleşmesine açıkça cast edilmiştir.';

NOTIFY pgrst, 'reload schema';


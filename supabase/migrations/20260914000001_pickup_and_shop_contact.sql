-- ============================================================================
-- "Gel Al" (mağazadan teslim) + kuryenin dükkân iletişim/konum bilgisine erişimi
-- ----------------------------------------------------------------------------
-- 1) shops.pickup_enabled: satıcı "Gel Al" özelliğini kendi panelinden açıp
--    kapatabilsin diye yeni bayrak. Varsayılan false — mevcut dükkânlarda
--    davranış değişmez, satıcı bilinçli olarak açmadıkça rozet/checkout
--    seçeneği görünmez.
-- 2) orders.is_pickup: sipariş self-pickup mu yoksa normal teslimat mı.
--    Kurye havuzu (get_available_orders_for_courier) ve aktif/atanmış
--    sipariş RPC'leri (get_courier_active_orders, get_courier_routed_order_offers)
--    bu bayrağı kullanarak self-pickup siparişleri tamamen dışarıda bırakır —
--    self-pickup siparişte kurye hiçbir aşamada devreye girmemeli.
-- 3) Kurye zaten dükkân adını görüyordu (s.name) ama telefon/adres/lat/lng
--    hiç dönmüyordu; kurye teslim almak için dükkânı arayamıyor/haritada
--    bulamıyordu. Üç RPC'ye de dükkânın phone/address/latitude/longitude
--    kolonları eklendi. Bunlar müşteri PII'si değil, dükkânın kendi genel
--    iletişim/adres bilgisi (zaten müşteri tarafında dükkân sayfasında
--    herkese açık) — bu nedenle atanmamış havuzda bile paylaşılması mevcut
--    "adres/telefon yalnız kabul edene açılır" müşteri-PII kuralını ihlal
--    etmiyor (o kural customer_phone/delivery_address_text'e özgü).
-- ============================================================================

ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS pickup_enabled boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.shops.pickup_enabled IS
  'Satıcı "Gel Al" (mağazadan teslim) özelliğini aktif etti mi. Satıcı panelinden kontrol edilir.';

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS is_pickup boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.orders.is_pickup IS
  'true ise müşteri siparişi kuryeyle değil, mağazadan bizzat ("Gel Al") teslim alacak. Kurye RPC''leri bu siparişleri hariç tutar.';

-- ----------------------------------------------------------------------------
-- get_available_orders_for_courier: genel havuz. Artık is_pickup siparişleri
-- hariç tutuyor (kurye devreye hiç girmemeli) ve dükkânın phone/address/
-- latitude/longitude kolonlarını da döndürüyor.
-- Dönen sütun seti değiştiği için (OUT parametreleri) CREATE OR REPLACE
-- yetmiyor — Postgres önce DROP ister.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_available_orders_for_courier();

CREATE OR REPLACE FUNCTION public.get_available_orders_for_courier()
RETURNS TABLE(
  id uuid,
  total numeric,
  shop_id uuid,
  shop_name text,
  created_at timestamp with time zone,
  item_count bigint,
  shop_phone text,
  shop_address text,
  shop_latitude numeric,
  shop_longitude numeric
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
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
    ) AS item_count,
    s.phone,
    s.address,
    s.latitude,
    s.longitude
  FROM public.orders AS o
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE o.status IN ('confirmed', 'preparing', 'ready')
    AND o.is_pickup = false
    AND COALESCE(s.has_own_courier, false) = false
    AND (SELECT auth.uid()) IS NOT NULL
    AND public.is_courier_role()
    AND public.is_courier_document_approved()
    AND o.user_id IS DISTINCT FROM (SELECT auth.uid())
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_assignments AS ca
      WHERE ca.order_id = o.id
        AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_order_rejections AS cor
      WHERE cor.order_id = o.id
        AND cor.courier_id = (SELECT auth.uid())
    )
  ORDER BY o.created_at ASC;
$function$;

-- DROP FUNCTION az önce eski grant'leri de sildi (anon hariç, authenticated +
-- service_role) — aynı yetkiyi açıkça geri veriyoruz, PUBLIC/anon'a sızmasın.
REVOKE ALL ON FUNCTION public.get_available_orders_for_courier() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_available_orders_for_courier()
  TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- get_courier_active_orders: kuryeye atanmış aktif siparişler. is_pickup
-- siparişler zaten havuza hiç düşmediği için buraya da giremez, yine de
-- savunma amaçlı filtre eklendi. Dükkân phone/address/lat/lng eklendi.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_courier_active_orders();

CREATE OR REPLACE FUNCTION public.get_courier_active_orders()
RETURNS TABLE(
  assignment_id uuid,
  assignment_status text,
  fee_amount numeric,
  assigned_at timestamp with time zone,
  order_id uuid,
  order_total numeric,
  order_status text,
  delivery_address_text text,
  customer_phone text,
  created_at timestamp with time zone,
  shop_name text,
  order_items_json jsonb,
  shop_phone text,
  shop_address text,
  shop_latitude numeric,
  shop_longitude numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
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
          ) ORDER BY oi.product_name, oi.quantity
        )
        FROM public.order_items AS oi
        WHERE oi.order_id = o.id
      ),
      '[]'::jsonb
    ),
    s.phone::text,
    s.address::text,
    s.latitude::numeric,
    s.longitude::numeric
  FROM public.courier_assignments AS ca
  JOIN public.orders AS o ON o.id = ca.order_id
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE (ca.courier_id = v_uid OR public.is_admin())
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
    AND o.is_pickup = false
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_work_offers AS cwo
      WHERE cwo.assignment_id = ca.id
        AND cwo.status = 'pending'
    )
  ORDER BY ca.assigned_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_courier_active_orders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_courier_active_orders()
  TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- get_courier_routed_order_offers: ret/devret sonrası hedeflenmiş teklifler.
-- Dükkân phone/address/lat/lng eklendi; is_pickup siparişler hariç tutuldu.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_courier_routed_order_offers();

CREATE OR REPLACE FUNCTION public.get_courier_routed_order_offers()
RETURNS TABLE(
  offer_id uuid,
  assignment_id uuid,
  fee_amount numeric,
  order_id uuid,
  order_total numeric,
  order_status text,
  delivery_address_text text,
  customer_phone text,
  created_at timestamp with time zone,
  shop_id uuid,
  shop_name text,
  order_items_json jsonb,
  shop_phone text,
  shop_address text,
  shop_latitude numeric,
  shop_longitude numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden | kurye rolü gerekli' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    cwo.id::uuid,
    ca.id::uuid,
    ca.fee_amount::numeric,
    o.id::uuid,
    o.total::numeric,
    o.status::text,
    o.delivery_address_text::text,
    o.customer_phone::text,
    o.created_at::timestamptz,
    o.shop_id::uuid,
    s.name::text,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'quantity', oi.quantity,
            'product_name', oi.product_name
          ) ORDER BY oi.product_name, oi.quantity
        )
        FROM public.order_items AS oi
        WHERE oi.order_id = o.id
      ),
      '[]'::jsonb
    ),
    s.phone::text,
    s.address::text,
    s.latitude::numeric,
    s.longitude::numeric
  FROM public.courier_work_offers AS cwo
  JOIN public.courier_assignments AS ca
    ON ca.id = cwo.assignment_id
   AND ca.order_id = cwo.order_id
   AND ca.courier_id = cwo.courier_id
  JOIN public.orders AS o ON o.id = cwo.order_id
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE cwo.work_type = 'order'
    AND cwo.status = 'pending'
    AND cwo.courier_id = v_uid
    AND ca.status = 'assigned'
    AND o.status = 'ready'
    AND o.is_pickup = false
  ORDER BY cwo.offered_at ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_courier_routed_order_offers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_courier_routed_order_offers()
  TO authenticated, service_role;

DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

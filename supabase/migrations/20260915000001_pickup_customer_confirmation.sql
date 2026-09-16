-- ============================================================================
-- "Gel Al" siparişini müşteri teslim aldığında kapatma + bekleyenleri izleme
-- ----------------------------------------------------------------------------
-- SORUN: Gel Al siparişi "Hazır"da kilitli kalıyordu. Satıcı panelinde ready
-- durumundaki tek aksiyon "Yola Çıkar" ve o da yalnız kendi kuryesi olan
-- satıcıya görünüyor; "Kurye Çağır" ise pickup'ta bilinçli olarak gizli.
-- Yani kuryesi olmayan satıcıda sipariş hiçbir zaman 'delivered' olmuyor ve
-- teslim anına bağlı TÜM kazanç zinciri hiç çalışmıyordu:
--   * create_seller_earnings_on_delivery  -> seller_earnings satırı
--   * update_shop_balance                 -> satıcı alacağı (admin_credit)
--   * satış sayacı + değerlendirme daveti
--
-- ÇÖZÜM: Teslim onayını MÜŞTERİ verir ("Teslim Aldım"). Para zaten peşin
-- bakiyeden tahsil edildiği için (Gel Al = bakiye ile ödeme), onay anında
-- sipariş 'delivered' olur ve yukarıdaki zincir normal akışıyla çalışır.
--
-- Müşteri onaylamazsa sipariş ASKIDA KALMASIN diye otomatik kapatma YOK
-- (yanlış otomatik ödeme riski); 2 günü aşanlar admin panelinde listelenir.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Müşterinin teslim onayı
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirm_pickup_order_received(p_order_id uuid)
RETURNS TABLE(
  r_order_id uuid,
  r_status text,
  r_delivered_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_order public.orders%ROWTYPE;
  v_seller_id uuid;
  v_shop_name text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'APP:order_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT o.* INTO v_order
  FROM public.orders AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  -- Yalnız siparişin sahibi (veya admin) onaylayabilir.
  IF v_order.user_id IS DISTINCT FROM v_uid AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:not_order_owner' USING ERRCODE = '42501';
  END IF;

  -- Bu akış yalnız "Gel Al" siparişleri içindir; kuryeli teslimatta onayı
  -- kurye complete_order_delivery ile verir.
  IF COALESCE(v_order.is_pickup, false) = false THEN
    RAISE EXCEPTION 'APP:not_pickup_order' USING ERRCODE = 'P0001';
  END IF;

  IF v_order.status = 'delivered' THEN
    -- Idempotent: çift dokunuşta hata yerine mevcut durumu döndür.
    RETURN QUERY SELECT v_order.id, v_order.status::text, v_order.delivered_at;
    RETURN;
  END IF;

  -- Satıcı "Hazır" demeden müşteri teslim aldım diyemez.
  IF v_order.status <> 'ready' THEN
    RAISE EXCEPTION 'APP:invalid_state | durum: %', v_order.status
      USING ERRCODE = 'P0001';
  END IF;

  -- Gel Al her zaman peşin ödemelidir. Ödenmemiş bir siparişi teslim
  -- saymak satıcıya karşılıksız alacak yazardı.
  IF v_order.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'APP:order_not_paid | ödeme durumu: %', v_order.payment_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
     SET status = 'delivered',
         delivered_at = now(),
         updated_at = now()
   WHERE id = p_order_id;

  SELECT s.owner_id, s.name INTO v_seller_id, v_shop_name
  FROM public.shops AS s
  WHERE s.id = v_order.shop_id;

  -- Satıcıya bilgi: kazanç bu anda işlenir.
  IF v_seller_id IS NOT NULL THEN
    PERFORM public.add_notification(
      p_user_id   => v_seller_id,
      p_type      => 'order_update',
      p_title     => 'Gel Al Siparişi Teslim Alındı',
      p_content   => 'Müşteri siparişi mağazadan teslim aldı, sipariş tamamlandı.',
      p_entity_id => p_order_id::text
    );
  END IF;

  -- Müşteriye değerlendirme daveti (kuryeli akıştaki ile aynı tip).
  PERFORM public.add_notification(
    p_user_id   => v_order.user_id,
    p_type      => 'order_delivered',
    p_title     => 'Siparişiniz Tamamlandı',
    p_content   => COALESCE(v_shop_name, 'Mağaza') ||
                   ' siparişinizi değerlendirmek için tıklayın.',
    p_entity_id => p_order_id::text
  );

  RETURN QUERY
  SELECT o.id, o.status::text, o.delivered_at
  FROM public.orders AS o
  WHERE o.id = p_order_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.confirm_pickup_order_received(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_pickup_order_received(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.confirm_pickup_order_received(uuid) IS
  'Gel Al siparişinde müşterinin "Teslim Aldım" onayı: ready -> delivered. Kazanç/bakiye trigger''ları normal akışla çalışır.';

-- ----------------------------------------------------------------------------
-- 2) Admin: onaylanmayı bekleyen Gel Al siparişleri
-- ----------------------------------------------------------------------------
-- Not: siparişin "ne zamandır hazır" olduğu updated_at üzerinden ölçülür;
-- ready durumundaki bir Gel Al siparişine başka hiçbir güncelleme gelmediği
-- için bu güvenilir bir vekildir (ayrı ready_at sütunu açmaya gerek yok).
CREATE OR REPLACE FUNCTION public.admin_list_pending_pickup_orders(
  p_min_days integer DEFAULT 2
)
RETURNS TABLE(
  order_id uuid,
  order_number text,
  order_number_int integer,
  total numeric,
  created_at timestamp with time zone,
  ready_since timestamp with time zone,
  days_waiting integer,
  shop_id uuid,
  shop_name text,
  shop_phone text,
  customer_id uuid,
  customer_name text,
  customer_phone text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_list_pending_pickup_orders: not admin'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    o.id,
    o.order_number::text,
    o.order_number_int,
    o.total,
    o.created_at,
    o.updated_at AS ready_since,
    GREATEST(0, EXTRACT(DAY FROM (now() - o.updated_at))::integer) AS days_waiting,
    s.id,
    s.name::text,
    s.phone::text,
    p.id,
    COALESCE(p.full_name, p.username, 'Müşteri')::text,
    COALESCE(o.customer_phone, p.phone)::text
  FROM public.orders AS o
  JOIN public.shops AS s ON s.id = o.shop_id
  LEFT JOIN public.profiles AS p ON p.id = o.user_id
  WHERE o.is_pickup = true
    AND o.status = 'ready'
    AND o.updated_at < (now() - make_interval(days => GREATEST(p_min_days, 0)))
  ORDER BY o.updated_at ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_pending_pickup_orders(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pending_pickup_orders(integer)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_list_pending_pickup_orders(integer) IS
  'Müşterisi teslim onayı vermemiş, N günden uzun süredir hazır bekleyen Gel Al siparişleri (varsayılan 2 gün). Otomatik kapatma yoktur, admin manuel karar verir.';

DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

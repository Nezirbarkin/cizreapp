-- ============================================================================
-- İade talebi "UPDATE requires a WHERE clause" hatası (2026-10-16)
-- ----------------------------------------------------------------------------
-- Uygulamadan gelen istekler authenticator rolüyle açılır ve bu rolde
-- session_preload_libraries = safeupdate var: WHERE'siz UPDATE/DELETE reddedilir.
-- create_return_request "tümünü iade et" dalında geçici tabloyu WHERE'siz
-- güncelliyordu → müşteri iade talebi açamıyordu. Canlı fonksiyon taramasında
-- aynı hatayı taşıyan admin_purge_analytics_events ve admin_clear_music_stats
-- de düzeltildi.
-- CLI ile çalışan testler safeupdate yüklemediği (ve LOAD izni olmadığı) için
-- görünmedi. Kontrol: canlı plpgsql gövdelerinde WHERE'siz UPDATE/DELETE taraması.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.create_return_request(p_order_id uuid, p_reason text, p_items jsonb DEFAULT NULL::jsonb)
 RETURNS return_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c_window_days CONSTANT integer := 14;
  v_uid          uuid := auth.uid();
  v_reason       text := btrim(COALESCE(p_reason, ''));
  v_order        record;
  v_items_sum    numeric;
  v_goods_paid   numeric;
  v_ratio        numeric;
  v_prev_refund  numeric;
  v_value        numeric := 0;
  v_refund       numeric;
  v_all_order    boolean;
  v_final        boolean;
  v_scope        text;
  v_line_count   integer;
  v_request      public.return_requests;
  v_label        text;
  v_bad          text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;

  IF length(v_reason) < 3 THEN
    RAISE EXCEPTION 'İade sebebi en az 3 karakter olmalı' USING ERRCODE = '22023';
  END IF;
  IF length(v_reason) > 1000 THEN
    RAISE EXCEPTION 'İade sebebi en fazla 1000 karakter olabilir' USING ERRCODE = '22023';
  END IF;

  SELECT id, user_id, shop_id, status::text AS status, total, delivery_fee,
         payment_method::text AS payment_method, payment_status::text AS payment_status,
         order_number, delivered_at, updated_at, created_at,
         commission_status::text AS commission_status
    INTO v_order
    FROM public.orders
   WHERE id = p_order_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sipariş bulunamadı' USING ERRCODE = 'P0002';
  END IF;

  IF v_order.user_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'Bu siparişe erişim yetkiniz yok' USING ERRCODE = '42501';
  END IF;

  IF v_order.status <> 'delivered' THEN
    RAISE EXCEPTION 'Yalnızca teslim edilmiş siparişler iade edilebilir' USING ERRCODE = 'P0001';
  END IF;

  IF v_order.payment_status = 'refunded' THEN
    RAISE EXCEPTION 'Bu siparişin ödemesi zaten iade edilmiş' USING ERRCODE = 'P0001';
  END IF;

  IF COALESCE(v_order.delivered_at, v_order.updated_at, v_order.created_at)
       < now() - make_interval(days => c_window_days) THEN
    RAISE EXCEPTION 'İade süresi doldu (teslimattan sonra % gün)', c_window_days
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (SELECT 1 FROM public.return_requests
              WHERE order_id = p_order_id AND status = 'pending') THEN
    RAISE EXCEPTION 'Bu sipariş için bekleyen bir iade talebiniz zaten var' USING ERRCODE = 'P0001';
  END IF;

  IF p_items IS NOT NULL AND jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Geçersiz ürün listesi' USING ERRCODE = '22023';
  END IF;

  -- Sipariş kalemleri + kalan iade edilebilir adet
  CREATE TEMP TABLE IF NOT EXISTS pg_temp.rr_lines (
    order_item_id uuid PRIMARY KEY,
    product_id    uuid,
    product_name  text,
    image_url     text,
    ordered_qty   integer,
    line_subtotal numeric,
    remaining_qty integer,
    req_qty       integer
  ) ON COMMIT DROP;
  TRUNCATE pg_temp.rr_lines;

  INSERT INTO pg_temp.rr_lines
  SELECT oi.id, oi.product_id, COALESCE(oi.product_name, 'Ürün'), oi.product_image_url,
         oi.quantity,
         COALESCE(oi.subtotal, COALESCE(oi.price, oi.product_price, 0) * oi.quantity),
         GREATEST(oi.quantity - public.return_reserved_quantity(oi.id), 0),
         0
    FROM public.order_items oi
   WHERE oi.order_id = p_order_id
     AND oi.quantity > 0;

  SELECT COALESCE(sum(line_subtotal), 0) INTO v_items_sum FROM pg_temp.rr_lines;
  IF v_items_sum <= 0 THEN
    RAISE EXCEPTION 'Bu siparişte iade edilebilir ürün yok' USING ERRCODE = 'P0001';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    -- WHERE şart: PostgREST oturumlarında safeupdate WHERE'siz UPDATE'i reddeder.
    UPDATE pg_temp.rr_lines SET req_qty = remaining_qty WHERE true;
  ELSE
    -- Sipariş dışı / bozuk kalem
    SELECT e ->> 'order_item_id' INTO v_bad
      FROM jsonb_array_elements(p_items) e
     WHERE jsonb_typeof(e) <> 'object'
        OR NOT EXISTS (SELECT 1 FROM pg_temp.rr_lines l
                        WHERE l.order_item_id::text = lower(COALESCE(e ->> 'order_item_id', '')))
     LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'Ürün bu siparişe ait değil' USING ERRCODE = '22023';
    END IF;

    -- (Kısa devre garanti olmadığından tür dönüşümü CASE içinde.)
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_items) e
                WHERE CASE WHEN COALESCE(e ->> 'quantity', '') ~ '^[0-9]{1,6}$'
                           THEN (e ->> 'quantity')::integer < 1
                           ELSE true END) THEN
      RAISE EXCEPTION 'İade adedi en az 1 olmalı' USING ERRCODE = '22023';
    END IF;

    UPDATE pg_temp.rr_lines l
       SET req_qty = x.qty
      FROM (SELECT (e ->> 'order_item_id')::uuid AS id,
                   sum((e ->> 'quantity')::integer)::integer AS qty
              FROM jsonb_array_elements(p_items) e
             GROUP BY 1) x
     WHERE l.order_item_id = x.id;

    SELECT product_name INTO v_bad
      FROM pg_temp.rr_lines WHERE req_qty > remaining_qty LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION '"%" için iade adedi kalan adetten fazla', v_bad USING ERRCODE = '22023';
    END IF;
  END IF;

  SELECT count(*) INTO v_line_count FROM pg_temp.rr_lines WHERE req_qty > 0;
  IF v_line_count = 0 THEN
    RAISE EXCEPTION 'Bu siparişte iade edilebilecek ürün kalmadı' USING ERRCODE = 'P0001';
  END IF;

  -- Tutarlar
  v_goods_paid := GREATEST(COALESCE(v_order.total, 0) - COALESCE(v_order.delivery_fee, 0), 0);
  v_ratio      := LEAST(v_goods_paid / v_items_sum, 1);

  SELECT COALESCE(sum(refund_amount), 0) INTO v_prev_refund
    FROM public.return_requests
   WHERE order_id = p_order_id AND status IN ('approved', 'completed');

  SELECT COALESCE(sum(line_subtotal / ordered_qty * req_qty), 0) INTO v_value
    FROM pg_temp.rr_lines WHERE req_qty > 0;

  v_final     := NOT EXISTS (SELECT 1 FROM pg_temp.rr_lines WHERE req_qty < remaining_qty);
  v_all_order := v_final AND NOT EXISTS (SELECT 1 FROM pg_temp.rr_lines WHERE remaining_qty < ordered_qty);
  v_scope     := CASE WHEN v_all_order THEN 'full' ELSE 'partial' END;

  IF v_final THEN
    v_refund := GREATEST(v_goods_paid - v_prev_refund, 0);
  ELSE
    v_refund := LEAST(round(v_value * v_ratio, 2), GREATEST(v_goods_paid - v_prev_refund, 0));
  END IF;

  INSERT INTO public.return_requests (
    order_id, user_id, shop_id, reason, status, return_scope,
    payment_method, refund_method, refund_amount, created_at
  ) VALUES (
    p_order_id, v_uid, v_order.shop_id, v_reason, 'pending', v_scope,
    v_order.payment_method,
    CASE WHEN v_order.commission_status = 'cash_collected' THEN 'seller_cash' ELSE 'balance' END,
    v_refund, now()
  )
  RETURNING * INTO v_request;

  INSERT INTO public.return_request_items (
    request_id, order_item_id, product_id, product_name, product_image_url,
    quantity, unit_price, line_total
  )
  SELECT v_request.id, order_item_id, product_id, product_name, image_url,
         req_qty,
         round(line_subtotal / ordered_qty, 2),
         round(line_subtotal / ordered_qty * req_qty, 2)
    FROM pg_temp.rr_lines
   WHERE req_qty > 0;

  v_label := COALESCE(v_order.order_number::text, substring(p_order_id::text, 1, 8));

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  SELECT p.id,
         'return_request',
         'Yeni İade Talebi',
         'Sipariş #' || v_label || ' için ' ||
           CASE WHEN v_scope = 'full' THEN 'tüm ürünlerin' ELSE v_line_count || ' ürünün' END ||
           ' iadesi istendi (₺' || to_char(v_refund, 'FM999999990.00') || '). Sebep: ' || v_reason,
         v_request.id::text,
         'return_request',
         jsonb_build_object('request_id', v_request.id, 'order_id', p_order_id,
                            'refund_amount', v_refund, 'return_scope', v_scope)
    FROM public.profiles p
   WHERE p.role = 'admin';

  RETURN v_request;
END;
$function$;


-- ── Aynı hata, önceden vardı: yönetici temizleme düğmeleri de uygulamadan
--    "DELETE requires a WHERE clause" ile düşüyordu (tam silme amaçlı).
-- admin_clear_music_stats()
CREATE OR REPLACE FUNCTION public.admin_clear_music_stats()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_deleted bigint;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_clear_music_stats: not admin' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.music_listening_stats WHERE true;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  DELETE FROM public.music_now_playing WHERE true;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, new_data)
  VALUES (auth.uid(), 'clear_music_stats', 'music_listening_stats', NULL,
          jsonb_build_object('deleted', v_deleted));
  RETURN v_deleted;
END;
$function$;

-- admin_purge_analytics_events(integer)
CREATE OR REPLACE FUNCTION public.admin_purge_analytics_events(p_older_than_days integer DEFAULT NULL::integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_deleted bigint;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_purge_analytics_events: not admin' USING ERRCODE = '42501';
  END IF;

  IF p_older_than_days IS NULL THEN
    DELETE FROM public.app_analytics_events WHERE true;
  ELSE
    DELETE FROM public.app_analytics_events
    WHERE created_at < now() - (GREATEST(p_older_than_days, 0) * interval '1 day');
  END IF;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';

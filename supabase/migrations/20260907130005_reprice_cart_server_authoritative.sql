-- =============================================================================
-- private.reprice_cart: online ödeme için sunucu-otoriter sepet fiyatlaması
-- =============================================================================
-- SORUN
-- -----
-- `iyzico-payment-init` edge function'ı, çekilecek tutarı TAMAMEN istemcinin
-- gönderdiği gövdeden alıyor (supabase/functions/iyzico-payment-init/index.ts):
--     :270  price: (item.price * item.quantity)     <- istemci fiyatı
--     :285  price: order_data.delivery_fee          <- istemci ücreti
--     :294  const paidPrice = order_data.total      <- istemci toplamı
-- Tek doğrulama `total > 0`. Fonksiyon ürün fiyatını DB'den HİÇ okumuyor
-- (tek select'i `select("id")`).
--
-- 20260907120001 `orders`/`order_items` tarafını kapattı, ancak iyzico
-- akışında sipariş HENÜZ YOK: istemci doğrudan payment-init'i çağırıyor,
-- sipariş callback'te oluşuyor. Yani kart 1 TL'ye çekilebiliyordu.
--
-- ÇÖZÜM
-- -----
-- Fiyatlama mantığı tek bir yerde toplanıyor. Edge function bu RPC'yi
-- çağırıp istemcinin gönderdiği TÜM finansal alanları atacak.
-- Trigger (private.enforce_order_item_price) ile AYNI birim fiyat
-- fonksiyonunu kullanır: private.authoritative_item_price.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION private.reprice_cart(
  p_items        jsonb,            -- [{product_id, quantity, flash_sale_id}]
  p_coupon_id    uuid DEFAULT NULL,
  p_delivery_fee numeric DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item        jsonb;
  v_pid         uuid;
  v_qty         integer;
  v_fsid        uuid;
  v_unit        numeric;
  v_line        numeric;
  v_items_out   jsonb := '[]'::jsonb;
  v_subtotal    numeric := 0;
  v_delivery    numeric := GREATEST(COALESCE(p_delivery_fee, 0), 0);
  v_coupon      numeric := 0;
  v_c           record;
  v_name        text;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'reprice_cart: bos sepet' USING ERRCODE = '22023';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_pid  := NULLIF(v_item->>'product_id', '')::uuid;
    v_qty  := GREATEST(COALESCE((v_item->>'quantity')::integer, 0), 0);
    v_fsid := NULLIF(v_item->>'flash_sale_id', '')::uuid;

    IF v_pid IS NULL OR v_qty < 1 THEN
      RAISE EXCEPTION 'reprice_cart: gecersiz kalem' USING ERRCODE = '22023';
    END IF;

    SELECT p.name INTO v_name FROM public.products p WHERE p.id = v_pid;
    IF v_name IS NULL THEN
      RAISE EXCEPTION 'reprice_cart: urun bulunamadi %', v_pid
        USING ERRCODE = '22023';
    END IF;

    v_unit := private.authoritative_item_price(v_pid, v_fsid);

    -- SMM ürünleri (price_per_1000) NULL döner; bu akışta desteklenmiyor.
    IF v_unit IS NULL THEN
      RAISE EXCEPTION 'reprice_cart: urun fiyatlandirilamadi %', v_pid
        USING ERRCODE = '22023';
    END IF;

    v_line     := ROUND(v_unit * v_qty, 2);
    v_subtotal := v_subtotal + v_line;

    v_items_out := v_items_out || jsonb_build_object(
      'product_id',   v_pid,
      'product_name', v_name,
      'quantity',     v_qty,
      'price',        v_unit,
      'line_total',   v_line
    );
  END LOOP;

  v_subtotal := ROUND(v_subtotal, 2);

  -- ---------------------------------------------------------------------------
  -- Kupon: istemcinin gönderdiği indirim tutarı YOK SAYILIR, kupon
  -- kaydından yeniden hesaplanır.
  -- ---------------------------------------------------------------------------
  IF p_coupon_id IS NOT NULL THEN
    SELECT c.* INTO v_c FROM public.coupons c WHERE c.id = p_coupon_id;

    IF FOUND
       AND COALESCE(v_c.is_active, false)
       AND (v_c.start_date IS NULL OR v_c.start_date <= NOW())
       AND (v_c.end_date   IS NULL OR v_c.end_date   >= NOW())
       AND (v_c.min_order_amount IS NULL OR v_subtotal >= v_c.min_order_amount)
       AND (v_c.max_usage  IS NULL OR COALESCE(v_c.used_count, 0)  < v_c.max_usage)
       AND (v_c.usage_limit IS NULL OR COALESCE(v_c.usage_count, 0) < v_c.usage_limit)
    THEN
      v_coupon := CASE
        WHEN v_c.discount_type = 'percentage'
          THEN v_subtotal * COALESCE(v_c.discount_value, 0) / 100.0
        ELSE COALESCE(v_c.discount_value, 0)
      END;

      IF v_c.max_discount_amount IS NOT NULL THEN
        v_coupon := LEAST(v_coupon, v_c.max_discount_amount);
      END IF;
    END IF;
  END IF;

  v_coupon := ROUND(LEAST(GREATEST(v_coupon, 0), v_subtotal), 2);

  RETURN jsonb_build_object(
    'items',           v_items_out,
    'subtotal',        v_subtotal,
    'coupon_discount', v_coupon,
    'delivery_fee',    ROUND(v_delivery, 2),
    'total',           ROUND(GREATEST(v_subtotal - v_coupon + v_delivery, 0), 2)
  );
END;
$$;

REVOKE ALL ON FUNCTION private.reprice_cart(jsonb, uuid, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.reprice_cart(jsonb, uuid, numeric) TO service_role;

-- Edge function service_role ile PostgREST üzerinden çağırdığı için
-- public şemada ince bir sarmalayıcı gerekiyor (PostgREST yalnız
-- exposed şemalardaki fonksiyonları görür).
CREATE OR REPLACE FUNCTION public.reprice_cart_internal(
  p_items        jsonb,
  p_coupon_id    uuid DEFAULT NULL,
  p_delivery_fee numeric DEFAULT 0
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.reprice_cart(p_items, p_coupon_id, p_delivery_fee);
$$;

REVOKE ALL ON FUNCTION public.reprice_cart_internal(jsonb, uuid, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reprice_cart_internal(jsonb, uuid, numeric) TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';

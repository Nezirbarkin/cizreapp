-- Dijital (SMM) sipariş toplamı birim yuvarlamasıyla eksik hesaplanıyordu.
--
-- Eski formül: birim = round(price_per_1000 / 1000, 4); toplam = round(birim × adet, 2).
-- 1000 adet fiyatı küçük olan serviste birim 4 haneye sığmıyor ve kırpılıyordu:
-- 0,24 TL / 1000 adet → birim 0,0002 → 1000 adet = 0,20 TL (doğrusu 0,24).
-- Müşteri vitrindeki fiyattan az ödüyor, satıcı/sağlayıcı farkı zarar ediyordu.
--
-- Yeni: toplam = round(price_per_1000 × adet / 1000, 2). Birim yalnız kayıt için
-- 6 haneyle saklanır (price_per_1000 2 haneli → ppk/1000 en fazla 5 hane, tam
-- sığar; böylece total_price = round(unit_price × quantity, 2) eşitliği korunur).
-- Paket dalı ve puan/ödeme hesabı değişmedi. Geçmiş siparişlere dokunulmaz.
-- İstemci karşılığı: lib/core/utils/digital_order_pricing.dart

ALTER TABLE public.digital_orders
  ALTER COLUMN unit_price TYPE numeric(14,6);

CREATE OR REPLACE FUNCTION public.create_digital_order_with_points(p_user_id uuid, p_product_id uuid, p_target_url text, p_quantity integer, p_idempotency_key text, p_use_points boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_product public.products%ROWTYPE;
  v_order public.digital_orders%ROWTYPE;
  v_settings public.ad_settings%ROWTYPE;
  v_account public.user_point_accounts%ROWTYPE;
  v_cash public.user_balances%ROWTYPE;
  v_point_entry public.point_ledger_entries%ROWTYPE;
  v_order_id uuid := gen_random_uuid();
  v_unit_price numeric(14,6);
  v_gross numeric(12,2);
  v_gross_cents bigint;
  v_discount_cents bigint := 0;
  v_points bigint := 0;
  v_cash_paid numeric(12,2);
  v_cash_before numeric(12,2);
  v_cash_after numeric(12,2);
  v_cash_tx uuid;
  v_existing_count integer;
  v_existing_service_id text;
  v_cash_found boolean := false;
  v_is_package boolean := false;
BEGIN
  IF COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    ''
  ) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) NOT BETWEEN 8 AND 200
     OR p_target_url IS NULL OR length(trim(p_target_url)) = 0 OR length(p_target_url) > 2000
     OR p_use_points IS NULL THEN
    RAISE EXCEPTION 'INVALID_ORDER_INPUT' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':' || p_idempotency_key, 71002)
  );
  SELECT * INTO v_order FROM public.digital_orders AS o
  WHERE o.user_id = p_user_id AND o.request_idempotency_key = p_idempotency_key;
  IF FOUND THEN
    IF v_order.product_id IS DISTINCT FROM p_product_id
       OR v_order.target_url IS DISTINCT FROM trim(p_target_url)
       OR v_order.quantity IS DISTINCT FROM p_quantity
       OR v_order.requested_use_points IS DISTINCT FROM p_use_points THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE = '23505';
    END IF;
    SELECT p.smm_service_id INTO v_existing_service_id
    FROM public.products AS p WHERE p.id = v_order.product_id;
    RETURN jsonb_build_object('digital_order_id', v_order.id, 'provider_id', v_order.provider_id,
      'smm_service_id', v_existing_service_id,
      'gross_total_try', v_order.gross_total_try, 'points_spent', v_order.points_spent,
      'points_discount_try', v_order.points_discount_try, 'cash_paid_try', v_order.cash_balance_paid_try,
      'delivery_mode', v_order.delivery_mode, 'duplicate', true);
  END IF;

  SELECT * INTO v_product FROM public.products AS p
  WHERE p.id = p_product_id AND p.is_available = true;
  IF NOT FOUND OR v_product.product_type IS DISTINCT FROM 'digital' OR p_quantity IS NULL THEN
    RAISE EXCEPTION 'DIGITAL_PRODUCT_INVALID' USING ERRCODE = '22023';
  END IF;
  -- Paket: sabit fiyat, sağlayıcı yok, satıcı elle teslim eder; her sipariş tek pakettir.
  v_is_package := v_product.digital_mode = 'package';
  IF v_is_package THEN
    IF p_quantity <> 1 OR v_product.price IS NULL OR v_product.price <= 0 THEN
      RAISE EXCEPTION 'DIGITAL_PRODUCT_INVALID' USING ERRCODE = '22023';
    END IF;
  ELSIF v_product.smm_provider_id IS NULL
     OR v_product.min_quantity IS NULL OR v_product.max_quantity IS NULL
     OR p_quantity < v_product.min_quantity OR p_quantity > v_product.max_quantity THEN
    RAISE EXCEPTION 'DIGITAL_PRODUCT_INVALID' USING ERRCODE = '22023';
  END IF;
  -- Different request idempotency keys for the same user/product must still
  -- serialize before evaluating max_orders_per_user.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':' || p_product_id::text, 71003)
  );
  IF v_product.max_orders_per_user IS NOT NULL THEN
    SELECT count(*) INTO v_existing_count FROM public.digital_orders AS o
    WHERE o.user_id = p_user_id AND o.product_id = p_product_id
      AND o.status::text NOT IN ('failed', 'refunded');
    IF v_existing_count >= v_product.max_orders_per_user THEN
      RAISE EXCEPTION 'DIGITAL_ORDER_LIMIT' USING ERRCODE = '54000';
    END IF;
  END IF;
  SELECT * INTO v_settings FROM public.ad_settings AS s WHERE s.id = 1;
  IF v_is_package THEN
    v_unit_price := round(v_product.price, 4);
    v_gross := round(v_product.price, 2);
  ELSE
    -- Toplam doğrudan 1000 adet fiyatından: birimi önce yuvarlamak ucuz
    -- serviste fiyatı düşürüyordu (0,24/1000 → 0,0002 × 1000 = 0,20 TL).
    v_unit_price := round(v_product.price_per_1000 / 1000.0, 6);
    v_gross := round(v_product.price_per_1000 * p_quantity / 1000.0, 2);
  END IF;
  v_gross_cents := round(v_gross * 100)::bigint;

  INSERT INTO public.user_point_accounts(user_id) VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_account FROM public.user_point_accounts AS a
  WHERE a.user_id = p_user_id FOR UPDATE;
  SELECT * INTO v_cash FROM public.user_balances AS b
  WHERE b.user_id = p_user_id FOR UPDATE;
  v_cash_found := FOUND;

  IF p_use_points AND v_settings.reward_points_spend_enabled
     AND v_settings.reward_points_eligible_products_enabled AND v_product.is_points_eligible THEN
    v_discount_cents := LEAST(
      floor(v_account.balance_points * 100.0 / v_settings.points_per_try)::bigint,
      floor(v_gross_cents * v_product.max_points_coverage_percent / 100.0)::bigint
    );
    v_points := (v_discount_cents * v_settings.points_per_try / 100)::bigint;
  END IF;
  v_cash_paid := round((v_gross_cents - v_discount_cents) / 100.0, 2);
  IF v_cash_paid > 0 AND (NOT v_cash_found OR v_cash.balance < v_cash_paid) THEN
    RAISE EXCEPTION 'INSUFFICIENT_COMBINED_BALANCE' USING ERRCODE = 'P0001';
  END IF;

  IF v_points > 0 THEN
    v_point_entry := public.reward_points_apply_entry(p_user_id, 'digital_order_debit', 'debit', v_points,
      'digital_order', v_order_id, 'digital-order-points:' || v_order_id,
      jsonb_build_object('points_per_try', v_settings.points_per_try, 'discount_cents', v_discount_cents));
  END IF;
  IF v_cash_paid > 0 THEN
    v_cash_before := v_cash.balance;
    v_cash_after := v_cash.balance - v_cash_paid;
    v_cash_tx := gen_random_uuid();
    UPDATE public.user_balances AS b SET balance = v_cash_after,
      total_spent = b.total_spent + v_cash_paid, updated_at = clock_timestamp() WHERE b.id = v_cash.id;
    INSERT INTO public.balance_transactions(id, user_id, type, amount, net_amount, balance_before, balance_after,
      reference_type, reference_id, status, description, payment_method, metadata)
    VALUES (v_cash_tx, p_user_id, 'order_payment', v_cash_paid, v_cash_paid, v_cash_before, v_cash_after,
      'digital_order', v_order_id, 'completed', 'Dijital sipariş TL bakiye bileşeni', 'balance',
      jsonb_build_object('composition_version', 1, 'points_are_not_cash', true));
  ELSE
    v_cash_after := COALESCE(v_cash.balance, 0);
  END IF;

  INSERT INTO public.digital_orders(id, user_id, product_id, provider_id, target_url, quantity,
    unit_price, total_price, status, balance_transaction_id, request_idempotency_key, requested_use_points,
    gross_total_try, points_spent, points_per_try_snapshot, points_discount_try,
    cash_balance_paid_try, point_debit_entry_id, payment_composition_version, reconciliation_status,
    delivery_mode)
  VALUES (v_order_id, p_user_id, p_product_id,
    CASE WHEN v_is_package THEN NULL ELSE v_product.smm_provider_id END, trim(p_target_url), p_quantity,
    v_unit_price, v_gross, 'pending', v_cash_tx, p_idempotency_key, p_use_points,
    v_gross, v_points, v_settings.points_per_try, v_discount_cents / 100.0,
    v_cash_paid, v_point_entry.id, 1,
    CASE WHEN v_is_package THEN 'not_required' ELSE 'pending_provider' END,
    CASE WHEN v_is_package THEN 'manual' ELSE 'provider' END) RETURNING * INTO v_order;

  RETURN jsonb_build_object('digital_order_id', v_order.id, 'provider_id', v_order.provider_id,
    'smm_service_id', CASE WHEN v_is_package THEN NULL ELSE v_product.smm_service_id END,
    'gross_total_try', v_gross,
    'points_spent', v_points, 'points_discount_try', v_discount_cents / 100.0,
    'cash_paid_try', v_cash_paid, 'point_balance_after', COALESCE(v_point_entry.balance_after_points, v_account.balance_points),
    'cash_balance_after', v_cash_after, 'reconciliation_status', v_order.reconciliation_status,
    'delivery_mode', v_order.delivery_mode, 'duplicate', false);
END;
$function$;

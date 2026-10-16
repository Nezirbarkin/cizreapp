-- Dijital ürünlerde "Paket" satış şekli (2026-10-16).
--
-- Bugüne kadar dijital ürün yalnız SMM'di: fiyat 1000 adet üzerinden
-- hesaplanır, müşteri adet seçer, sipariş sağlayıcı API'sine otomatik gider.
-- Paket modunda satıcı sabit fiyatlı bir paket satar (ör. "1000 takipçi —
-- ₺50"): müşteri adet seçmez (her sipariş 1 paket), ürün fiyatı kadar ödeme
-- alınır, sağlayıcı yoktur; satıcı teslimi elle yapıp siparişi "Tamamlandı"
-- işaretler (ya da iptal eder → tam iade).
--
--   * products.digital_mode ('smm' | 'package'); paket satırında sağlayıcı /
--     servis / 1000 adet fiyatı / min-max alanları tetikleyiciyle temizlenir,
--     böylece smm-sync-products (smm_provider_id ile süzer) paketlere dokunmaz.
--   * chk_digital_fields iki mod için yeniden yazıldı.
--   * digital_orders.provider_id artık boş olabilir; delivery_mode
--     ('provider' | 'manual') sipariş anının fotoğrafıdır (ürün sonra mod
--     değiştirse de sipariş kendi akışında kalır).
--   * create_digital_order_with_points: paket dalı (adet = 1, brüt = price).
--     Puan/TL dağılımı, kullanıcı başı limit ve idempotency aynen geçerli.
--   * RLS: manuel siparişi ürünün mağaza sahibi görür (sağlayıcısı olmadığı
--     için eski "sağlayıcı sahibi" kuralı onu kapsamıyordu).
--   * Bildirim: yeni paket siparişinde satıcıya, teslim/iptalde alıcıya.
--   * Eski create_digital_order(uuid,uuid,text,integer): 2026-07-30 cutover
--     belgesine göre tüm rollerden kapalı olmalıydı ama canlıda authenticated
--     EXECUTE'u açıktı. İçinde yetki kontrolü yok (p_user_id istemciden gelir,
--     DEFINER olarak deduct_from_balance çağırır) → başka kullanıcının
--     bakiyesinden sipariş açılabiliyordu. Hiçbir istemci/Edge Function
--     çağırmıyor (git geçmişinde yalnız eski smm-order-create service-role ile).

BEGIN;

-- ── 1) Ürün: satış şekli ────────────────────────────────────────────────────
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS digital_mode text NOT NULL DEFAULT 'smm';

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_digital_mode_check;
ALTER TABLE public.products ADD CONSTRAINT products_digital_mode_check
  CHECK (digital_mode IN ('smm', 'package'));

COMMENT ON COLUMN public.products.digital_mode IS
  'Dijital ürün satış şekli: smm = 1000 adet fiyatı × adet, sağlayıcıya otomatik; package = sabit fiyat (price), adet 1, satıcı elle teslim eder.';

CREATE OR REPLACE FUNCTION public.products_normalize_digital_mode()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF NEW.product_type IS DISTINCT FROM 'digital' THEN
    NEW.digital_mode := 'smm';
    RETURN NEW;
  END IF;
  IF NEW.digital_mode = 'package' THEN
    NEW.smm_provider_id := NULL;
    NEW.smm_service_id := NULL;
    NEW.price_per_1000 := NULL;
    NEW.min_quantity := NULL;
    NEW.max_quantity := NULL;
    NEW.smm_disabled_kind := NULL;
    NEW.smm_disabled_reason := NULL;
    -- SMM'den pakete geçen ürünün sağlayıcı karşılaştırma tabanı artık anlamsız.
    IF TG_OP = 'UPDATE' AND OLD.smm_provider_id IS NOT NULL THEN
      DELETE FROM public.smm_product_baselines WHERE product_id = NEW.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.products_normalize_digital_mode() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_products_normalize_digital_mode ON public.products;
CREATE TRIGGER trg_products_normalize_digital_mode
  BEFORE INSERT OR UPDATE OF product_type, digital_mode, smm_provider_id, smm_service_id,
    price_per_1000, min_quantity, max_quantity
  ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.products_normalize_digital_mode();

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS chk_digital_fields;
ALTER TABLE public.products ADD CONSTRAINT chk_digital_fields CHECK (
  product_type <> 'digital'
  OR (digital_mode = 'smm'
      AND smm_provider_id IS NOT NULL AND smm_service_id IS NOT NULL
      AND price_per_1000 IS NOT NULL AND min_quantity IS NOT NULL AND max_quantity IS NOT NULL)
  OR (digital_mode = 'package' AND smm_provider_id IS NULL AND price > 0)
);

-- ── 2) Sipariş: teslim şekli ────────────────────────────────────────────────
ALTER TABLE public.digital_orders ALTER COLUMN provider_id DROP NOT NULL;
ALTER TABLE public.digital_orders
  ADD COLUMN IF NOT EXISTS delivery_mode text NOT NULL DEFAULT 'provider';

ALTER TABLE public.digital_orders DROP CONSTRAINT IF EXISTS digital_orders_delivery_mode_check;
ALTER TABLE public.digital_orders ADD CONSTRAINT digital_orders_delivery_mode_check CHECK (
  (delivery_mode = 'provider' AND provider_id IS NOT NULL)
  OR (delivery_mode = 'manual' AND provider_id IS NULL)
);

COMMENT ON COLUMN public.digital_orders.delivery_mode IS
  'provider = SMM sağlayıcısına otomatik iletildi; manual = paket, satıcı elle teslim eder (provider_id NULL).';

-- Mevcut kural aynen korunur (yinelenen user_id koşulu atıldı); yalnız son
-- satır eklendi: manuel siparişi ürünün mağaza sahibi görür.
ALTER POLICY digital_orders_select_merged ON public.digital_orders
  USING (
    (user_id = (SELECT auth.uid()))
    OR ((SELECT profiles.role FROM public.profiles
          WHERE profiles.id = (SELECT auth.uid())) = 'admin'::public.user_role)
    OR (provider_id IN (
          SELECT sp.id
            FROM public.smm_providers sp
            JOIN public.shops s ON s.id = sp.owner_id AND sp.owner_type = 'seller'::public.smm_owner_type
           WHERE s.owner_id = (SELECT auth.uid())))
    OR (EXISTS (
          SELECT 1 FROM public.smm_providers sp
           WHERE sp.id = digital_orders.provider_id AND sp.owner_id = (SELECT auth.uid())))
    OR (delivery_mode = 'manual' AND product_id IN (
          SELECT p.id
            FROM public.products p
            JOIN public.shops s ON s.id = p.shop_id
           WHERE s.owner_id = (SELECT auth.uid())))
  );

-- ── 3) Sipariş rezervasyonu: paket dalı ─────────────────────────────────────
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
  v_unit_price numeric(12,4);
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
    v_unit_price := round(v_product.price_per_1000 / 1000.0, 4);
    v_gross := round(v_unit_price * p_quantity, 2);
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

-- ── 4) Bildirimler (yalnız manuel/paket siparişler) ─────────────────────────
-- Yeni sipariş → satıcıya "teslim bekliyor"; teslim/iptal → alıcıya.
-- SMM siparişlerinin mevcut bildirim akışına dokunulmaz.
CREATE OR REPLACE FUNCTION public.notify_manual_digital_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_seller_id uuid;
  v_product_name text;
  v_customer_name text;
  v_status text := NEW.status::text;
BEGIN
  SELECT s.owner_id, p.name INTO v_seller_id, v_product_name
    FROM public.products p
    JOIN public.shops s ON s.id = p.shop_id
   WHERE p.id = NEW.product_id;

  IF TG_OP = 'INSERT' THEN
    IF v_seller_id IS NULL THEN RETURN NEW; END IF;
    SELECT COALESCE(NULLIF(pr.full_name, ''), pr.username, 'Bir müşteri')
      INTO v_customer_name
      FROM public.profiles pr WHERE pr.id = NEW.user_id;
    INSERT INTO public.notifications (user_id, type, title, content, entity_id)
    VALUES (
      v_seller_id,
      'seller_new_digital_order',
      'Yeni paket siparişi — teslim bekliyor',
      COALESCE(v_customer_name, 'Bir müşteri') || ', ' ||
        COALESCE(v_product_name, 'dijital paket') || ' paketini satın aldı (₺' ||
        to_char(NEW.gross_total_try, 'FM999999990.00') ||
        '). Teslim edince Dijital Siparişler''den "Tamamlandı" olarak işaretleyin.',
      NEW.id::text
    );
  ELSIF v_status IS DISTINCT FROM OLD.status::text
        AND v_status IN ('completed', 'canceled', 'refunded', 'failed') THEN
    INSERT INTO public.notifications (user_id, type, title, content, entity_id)
    VALUES (
      NEW.user_id,
      'digital_order_status',
      CASE WHEN v_status = 'completed' THEN 'Paketiniz teslim edildi'
           ELSE 'Paket siparişiniz iptal edildi' END,
      CASE WHEN v_status = 'completed'
           THEN COALESCE(v_product_name, 'Dijital paket') || ' siparişiniz satıcı tarafından teslim edildi.'
           ELSE COALESCE(v_product_name, 'Dijital paket') || ' siparişiniz iptal edildi; ödemeniz puan/TL kaynağına iade edildi.'
      END,
      NEW.id::text
    );
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'notify_manual_digital_order failed for digital_order %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_manual_digital_order() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_digital_orders_manual_notify ON public.digital_orders;
CREATE TRIGGER trg_digital_orders_manual_notify
  AFTER INSERT OR UPDATE OF status ON public.digital_orders
  FOR EACH ROW
  WHEN (NEW.delivery_mode = 'manual')
  EXECUTE FUNCTION public.notify_manual_digital_order();

-- ── 5) Eski puansız rezervasyon RPC'si kapatılır ───────────────────────────
REVOKE ALL ON FUNCTION public.create_digital_order(uuid, uuid, text, integer)
  FROM PUBLIC, anon, authenticated;

-- ── 6) Son denetim ──────────────────────────────────────────────────────────
DO $$
BEGIN
  IF has_function_privilege('authenticated',
       'public.create_digital_order(uuid,uuid,text,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'create_digital_order hâlâ authenticated tarafından çalıştırılabiliyor';
  END IF;
  IF has_function_privilege('authenticated',
       'public.create_digital_order_with_points(uuid,uuid,text,integer,text,boolean)', 'EXECUTE')
     AND position('SERVICE_ROLE_REQUIRED' IN pg_get_functiondef(
       'public.create_digital_order_with_points(uuid,uuid,text,integer,text,boolean)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'create_digital_order_with_points service_role korumasını kaybetti';
  END IF;
  IF EXISTS (SELECT 1 FROM public.digital_orders
              WHERE delivery_mode = 'provider' AND provider_id IS NULL) THEN
    RAISE EXCEPTION 'sağlayıcısız provider siparişi var';
  END IF;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- Ana sepet ödemesi → sunucu-otoriteli oturum akışı (2026-10-17)
-- ----------------------------------------------------------------------------
-- Ana sepetin iki ödeme ekranı (checkout_screen / multi_shop_checkout_screen)
-- siparişi istemciden orders/order_items INSERT ederek oluşturuyordu. Yeni
-- sürüm yalnız private.prepare_checkout_session → commit_*_order zincirini
-- kullanır; istemci hiçbir tutar göndermez. Oturum akışı canlıda hiç
-- kullanılmamıştı (0 oturum) ve ana sepetin ihtiyaçlarını karşılamıyordu:
--
--   * Çok mağazalı sepette prepare "record v_shop is not assigned yet" ile
--     düşüyordu (komisyon tek mağaza kaydından okunuyordu).
--   * commit_* order_items'a olmayan variant_data sütununu yazıyordu.
--   * Flaş rezervasyonları oturuma hiç bağlanmıyordu (UPDATE ... WHERE
--     session_id = gen_random_uuid() hiçbir satırı tutmaz) → satılan flaş
--     adetleri sayılmıyordu.
--   * Gel Al (is_pickup), mağaza başına kupon, minimum sepet, ücretsiz sipariş
--     sınırı, satıcıya "Yeni Sipariş" bildirimi, "2 al 1 bakiye" kampanyası ve
--     tam teslimat adresi metni yoktu; kapıda kart 'card_on_delivery' olarak
--     yazılıyordu (uygulama enum adı 'cardOnDelivery'; aksi halde "Kapıda
--     Nakit" görünür).
--   * Bakiye ödemesi kendi defter kaydını reference_id = rastgele uuid ile
--     yazıyordu; iade akışları kaydı sipariş kimliğiyle arar. Artık eski akışla
--     aynı public.use_balance_for_order(p_order_id) kullanılır.
--   * Online ödeme: iyzico geri çağrısı complete_online_payment'ı çağırır;
--     oturumlu ödemelerde artık siparişler oturumdan oluşturulur.
--
-- Ek düzeltmeler:
--   * resync_order_totals kuponu iki kez düşüyordu: sözleşme gereği
--     discount = coupon_discount = kupon tutarı (bkz. 20261016000010), tetikleyici
--     ikisini de toplamdan çıkarıyordu (100 + 15 − 10 kupon → 95). Artık bir kez.
--   * Oturumlu siparişin iptalinde flaş adetleri geri verilir (eski akışın
--     talep defteri bu siparişleri bilerek atlıyor).
--
-- public.coupons tablosu (0 satır) sepette hiç uygulanamıyor (validate_coupon
-- mağaza kapsamlı shop_coupons okur); oturum akışı da yalnız shop_coupons kabul eder.
--
-- Flaş satış: sepete eklerken alınan talep (private.flash_sale_claims) artık
-- ödemenin doğruluğu için gerekmez. prepare rezervasyon açar (kullanıcının kendi
-- talebi kullanılabilir stok sayılır); commit talebi tüketir, kalan adedi
-- sold_count'a ekler. Oturum yarıda kalırsa talep sepette olduğu gibi durur.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Oturum tablosu: mağaza bazlı döküm
-- ---------------------------------------------------------------------------
ALTER TABLE private.server_checkout_sessions
  ADD COLUMN IF NOT EXISTS sub_orders jsonb,
  ADD COLUMN IF NOT EXISTS sub_order_coupon_ids jsonb,
  ADD COLUMN IF NOT EXISTS pickup_shop_ids uuid[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN private.server_checkout_sessions.sub_orders IS
  'Mağaza başına sipariş dökümü (shop_id, shop_name, subtotal, delivery_fee, coupon_id, coupon_discount, total, commission_amount, is_pickup, delivery_address_text). commit bunu siparişe çevirir.';

-- ---------------------------------------------------------------------------
-- 1) prepare_checkout_session (imza ve dönüş değişti → DROP + CREATE)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.prepare_checkout_session(jsonb, uuid, text, text, uuid, text, text, jsonb, uuid);
DROP FUNCTION IF EXISTS private.prepare_checkout_session(jsonb, uuid, text, text, uuid, text, jsonb, uuid);

CREATE FUNCTION private.prepare_checkout_session(
  p_items           jsonb,
  p_address_id      uuid,
  p_payment_method  text,
  p_idempotency_key text,
  p_coupon_ids      uuid[] DEFAULT NULL,
  p_pickup_shop_ids uuid[] DEFAULT NULL,
  p_notes           text   DEFAULT NULL,
  p_invoice_data    jsonb  DEFAULT NULL
)
RETURNS TABLE(
  session_id uuid, idempotency_key text, payment_method text, currency text,
  status text, expires_at timestamptz,
  server_subtotal numeric, server_delivery_fee numeric, server_discount numeric,
  server_coupon_discount numeric, server_commission_amount numeric, server_total numeric,
  items jsonb, sub_orders jsonb, delivery_address jsonb, notes text, warnings jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
#variable_conflict use_column
DECLARE
  v_user        uuid := auth.uid();
  v_now         timestamptz := now();
  v_pm          text;
  v_items_in    jsonb := p_items;
  v_existing    private.server_checkout_sessions%ROWTYPE;
  v_address     public.addresses%ROWTYPE;
  v_full_addr   text;
  v_item        jsonb;
  v_pid         uuid;
  v_qty         integer;
  v_fsid        uuid;
  v_p           record;
  v_fs          record;
  v_c           record;
  v_shop        record;
  v_unit        numeric;
  v_line        numeric;
  v_items       jsonb := '[]'::jsonb;
  v_warnings    jsonb := '[]'::jsonb;
  v_flash_need  jsonb := '{}'::jsonb;
  v_shop_ids    uuid[] := '{}';
  v_pickups     uuid[] := '{}';
  v_coupon_by_shop jsonb := '{}'::jsonb;
  v_cid         uuid;
  v_sale        text;
  v_need        integer;
  v_reserved    integer;
  v_claim       integer;
  v_avail       integer;
  v_sid         uuid;
  v_sub         numeric;
  v_fee         numeric;
  v_disc        numeric;
  v_total       numeric;
  v_rate        numeric;
  v_comm        numeric;
  v_max_fee     numeric;
  v_all_free    boolean;
  v_is_pickup   boolean;
  v_addr_text   text;
  v_multi       boolean;
  v_msg         text;
  v_sub_orders  jsonb := '[]'::jsonb;
  v_sub_subt    jsonb := '{}'::jsonb;
  v_sub_fees    jsonb := '{}'::jsonb;
  v_sub_discs   jsonb := '{}'::jsonb;
  v_t_sub       numeric := 0;
  v_t_fee       numeric := 0;
  v_t_disc      numeric := 0;
  v_t_comm      numeric := 0;
  v_free_count  integer := 0;
  v_prev_free   integer;
  v_session_id  uuid := gen_random_uuid();
  v_expires_at  timestamptz := v_now + interval '15 minutes';
  v_addr_snap   jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication gerekli (auth.uid() null)' USING ERRCODE = '42501';
  END IF;

  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 OR length(p_idempotency_key) > 128 THEN
    RAISE EXCEPTION 'idempotency_key gerekli (8-128 karakter)' USING ERRCODE = '22023';
  END IF;

  v_pm := CASE lower(btrim(COALESCE(p_payment_method, '')))
            WHEN 'cash'             THEN 'cash'
            WHEN 'cod'              THEN 'cash'
            WHEN 'card_on_delivery' THEN 'card_on_delivery'
            WHEN 'cardondelivery'   THEN 'card_on_delivery'
            WHEN 'balance'          THEN 'balance'
            WHEN 'online'           THEN 'online'
          END;
  IF v_pm IS NULL THEN
    RAISE EXCEPTION 'Gecersiz payment_method: %', p_payment_method USING ERRCODE = '22023';
  END IF;

  -- İlk istemci sürümü p_items'ı JSON metni olarak gönderiyordu.
  IF jsonb_typeof(v_items_in) = 'string' THEN
    v_items_in := (v_items_in #>> '{}')::jsonb;
  END IF;
  IF v_items_in IS NULL OR jsonb_typeof(v_items_in) <> 'array'
     OR jsonb_array_length(v_items_in) = 0 THEN
    RAISE EXCEPTION 'APP: empty_cart | Sepetiniz boş' USING ERRCODE = 'P0001';
  END IF;
  IF jsonb_array_length(v_items_in) > 100 THEN
    RAISE EXCEPTION 'Cok fazla kalem (en fazla 100)' USING ERRCODE = '22023';
  END IF;
  IF p_notes IS NOT NULL AND length(p_notes) > 500 THEN
    RAISE EXCEPTION 'APP: notes_too_long | Sipariş notu 500 karakteri geçemez' USING ERRCODE = 'P0001';
  END IF;

  -- 1) Idempotent tekrar: aynı anahtar aynı oturumu döndürür
  SELECT s.* INTO v_existing
  FROM private.server_checkout_sessions s
  WHERE s.user_id = v_user AND s.idempotency_key = p_idempotency_key;

  IF FOUND THEN
    IF v_existing.status = 'pending' AND v_existing.expires_at < v_now THEN
      UPDATE private.server_checkout_sessions s
         SET status = 'expired', updated_at = v_now
       WHERE s.id = v_existing.id;
      v_existing.status := 'expired';
    END IF;
    RETURN QUERY SELECT
      v_existing.id, v_existing.idempotency_key, v_existing.payment_method,
      v_existing.currency::text, v_existing.status, v_existing.expires_at,
      v_existing.server_subtotal, v_existing.server_delivery_fee, v_existing.server_discount,
      v_existing.server_coupon_discount, v_existing.server_commission_amount, v_existing.server_total,
      v_existing.items_snapshot, COALESCE(v_existing.sub_orders, '[]'::jsonb),
      v_existing.delivery_address_snapshot, v_existing.notes, '[]'::jsonb;
    RETURN;
  END IF;

  -- 2) Adres: bu kullanıcıya ait olmalı (Gel Al'da da telefon için gerekir)
  IF p_address_id IS NULL THEN
    RAISE EXCEPTION 'APP: address_required | Lütfen teslimat adresi seçin' USING ERRCODE = 'P0001';
  END IF;
  SELECT a.* INTO v_address
  FROM public.addresses a
  WHERE a.id = p_address_id AND a.user_id = v_user;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Adres bulunamadi veya bu kullaniciya ait degil' USING ERRCODE = '42501';
  END IF;
  -- Address.fullAddress (Dart) ile aynı biçim
  v_full_addr := concat_ws(', ',
    v_address.address_line1,
    NULLIF(v_address.address_line2, ''),
    NULLIF(v_address.district, ''),
    v_address.city,
    NULLIF(v_address.postal_code, ''));

  -- 3) Kalemler: fiyat order_items tetikleyicisiyle aynı fonksiyondan
  FOR v_item IN SELECT e FROM jsonb_array_elements(v_items_in) AS e
  LOOP
    v_pid  := NULLIF(v_item->>'product_id', '')::uuid;
    v_qty  := COALESCE((v_item->>'quantity')::integer, 0);
    v_fsid := NULLIF(v_item->>'flash_sale_id', '')::uuid;

    IF v_pid IS NULL THEN
      RAISE EXCEPTION 'Gecersiz product_id: %', v_item->>'product_id' USING ERRCODE = '22023';
    END IF;
    IF v_qty < 1 OR v_qty > 100 THEN
      RAISE EXCEPTION 'APP: invalid_quantity | Geçersiz ürün adedi (%)', v_qty USING ERRCODE = 'P0001';
    END IF;

    SELECT p.id, p.name, p.shop_id, p.image_url, p.is_available, p.stock_quantity,
           COALESCE(p.stock_unlimited, false) AS stock_unlimited, p.product_type,
           p.min_order_quantity, p.max_order_quantity, p.price_per_1000,
           s.name AS shop_name, s.is_active AS shop_active
      INTO v_p
      FROM public.products p
      JOIN public.shops s ON s.id = p.shop_id
     WHERE p.id = v_pid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'APP: product_not_found | Sepetinizdeki bir ürün artık satışta değil. Lütfen sepetinizi güncelleyin.'
        USING ERRCODE = 'P0001';
    END IF;
    IF v_p.is_available IS FALSE THEN
      RAISE EXCEPTION 'APP: product_unavailable | "%" şu an satışta değil', v_p.name USING ERRCODE = 'P0001';
    END IF;
    IF v_p.shop_active IS FALSE THEN
      RAISE EXCEPTION 'APP: shop_inactive | "%" mağazası şu an sipariş almıyor', v_p.shop_name USING ERRCODE = 'P0001';
    END IF;
    IF v_p.price_per_1000 IS NOT NULL THEN
      RAISE EXCEPTION 'APP: not_cart_purchasable | "%" sepetten satın alınamaz', v_p.name USING ERRCODE = 'P0001';
    END IF;
    IF NOT v_p.stock_unlimited AND v_p.stock_quantity IS NOT NULL AND v_p.stock_quantity < v_qty THEN
      RAISE EXCEPTION 'APP: insufficient_stock | "%" için yeterli stok yok (kalan: %)',
        v_p.name, GREATEST(v_p.stock_quantity, 0) USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(v_p.product_type, 'normal') <> 'digital' THEN
      IF v_p.min_order_quantity IS NOT NULL AND v_qty < v_p.min_order_quantity THEN
        RAISE EXCEPTION 'APP: min_quantity | "%" için en az % adet sipariş verilebilir',
          v_p.name, v_p.min_order_quantity USING ERRCODE = 'P0001';
      END IF;
      IF v_p.max_order_quantity IS NOT NULL AND v_qty > v_p.max_order_quantity THEN
        RAISE EXCEPTION 'APP: max_quantity | "%" için en fazla % adet sipariş verilebilir',
          v_p.name, v_p.max_order_quantity USING ERRCODE = 'P0001';
      END IF;
    END IF;

    -- Flaş: yalnız sepet satırı bir fırsattan geldiyse ve fırsat sürüyorsa
    IF v_fsid IS NOT NULL THEN
      SELECT fs.id, fs.is_active, fs.start_at, fs.end_at INTO v_fs
        FROM public.flash_sales fs
       WHERE fs.id = v_fsid AND fs.product_id = v_pid
       FOR UPDATE;
      IF NOT FOUND OR v_fs.is_active IS NOT TRUE
         OR v_now < v_fs.start_at OR v_now >= v_fs.end_at THEN
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code', 'flash_ended', 'product_id', v_pid, 'product_name', v_p.name));
        v_fsid := NULL;
      END IF;
    END IF;

    v_unit := private.authoritative_item_price(v_pid, v_fsid);
    IF v_unit IS NULL THEN
      RAISE EXCEPTION 'APP: not_cart_purchasable | "%" sepetten satın alınamaz', v_p.name USING ERRCODE = 'P0001';
    END IF;
    v_unit := round(v_unit, 2);
    v_line := round(v_unit * v_qty, 2);

    IF v_fsid IS NOT NULL THEN
      v_flash_need := v_flash_need || jsonb_build_object(v_fsid::text,
        COALESCE((v_flash_need->>v_fsid::text)::integer, 0) + v_qty);
    END IF;
    IF NOT (v_p.shop_id = ANY(v_shop_ids)) THEN
      v_shop_ids := v_shop_ids || v_p.shop_id;
    END IF;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'product_id',    v_pid,
      'product_name',  v_p.name,
      'shop_id',       v_p.shop_id,
      'shop_name',     v_p.shop_name,
      'image_url',     v_p.image_url,
      'quantity',      v_qty,
      'unit_price',    v_unit,
      'subtotal',      v_line,
      'line_total',    v_line,
      'flash_sale_id', v_fsid,
      'flash_price',   CASE WHEN v_fsid IS NOT NULL THEN v_unit END,
      'is_flash_sale', v_fsid IS NOT NULL
    ));
  END LOOP;

  -- 4) Flaş stok: satılan + diğer aktif rezervasyonlar düşülür; kullanıcının
  --    sepete eklerken aldığı talep zaten sold_count içinde olduğundan onun
  --    için kullanılabilir sayılır.
  FOR v_sale, v_need IN SELECT key, value::integer FROM jsonb_each_text(v_flash_need)
  LOOP
    IF v_need > 100 THEN
      RAISE EXCEPTION 'APP: invalid_quantity | Bir fırsattan en fazla 100 adet alınabilir' USING ERRCODE = 'P0001';
    END IF;
    SELECT fs.stock_limit, fs.sold_count, pr.name INTO v_fs
      FROM public.flash_sales fs
      JOIN public.products pr ON pr.id = fs.product_id
     WHERE fs.id = v_sale::uuid;
    SELECT COALESCE(SUM(r.quantity), 0)::integer INTO v_reserved
      FROM private.flash_sale_reservations r
     WHERE r.sale_id = v_sale::uuid AND r.status = 'active' AND r.expires_at > v_now;
    SELECT COALESCE(SUM(c.quantity), 0)::integer INTO v_claim
      FROM private.flash_sale_claims c
     WHERE c.user_id = v_user AND c.sale_id = v_sale::uuid;
    v_avail := v_fs.stock_limit - v_fs.sold_count - v_reserved + LEAST(v_claim, v_need);
    IF v_avail < v_need THEN
      RAISE EXCEPTION 'APP: flash_stock | "%" fırsatında yeterli stok kalmadı (kalan: %)',
        v_fs.name, GREATEST(v_avail, 0) USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  v_multi := cardinality(v_shop_ids) > 1;

  -- 5) Gel Al: yalnız sepetteki ve pickup_enabled mağazalar; peşin bakiye
  IF p_pickup_shop_ids IS NOT NULL THEN
    SELECT COALESCE(array_agg(DISTINCT x), '{}') INTO v_pickups
      FROM unnest(p_pickup_shop_ids) AS x
     WHERE x IS NOT NULL AND x = ANY(v_shop_ids);
  END IF;
  IF cardinality(v_pickups) > 0 THEN
    IF v_pm <> 'balance' THEN
      RAISE EXCEPTION 'APP: pickup_requires_balance | Gel Al siparişleri yalnızca bakiye ile ödenebilir'
        USING ERRCODE = 'P0001';
    END IF;
    SELECT s.name INTO v_shop
      FROM public.shops s
     WHERE s.id = ANY(v_pickups) AND s.pickup_enabled IS NOT TRUE
     LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'APP: pickup_unavailable | "%" mağazası Gel Al seçeneği sunmuyor', v_shop.name
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- 6) Kuponlar: mağaza başına en fazla bir shop_coupons kaydı
  IF p_coupon_ids IS NOT NULL THEN
    FOR v_cid IN SELECT DISTINCT x FROM unnest(p_coupon_ids) AS x WHERE x IS NOT NULL
    LOOP
      SELECT c.* INTO v_c FROM public.shop_coupons c WHERE c.id = v_cid FOR UPDATE;
      IF NOT FOUND OR NOT (v_c.shop_id = ANY(v_shop_ids)) THEN
        RAISE EXCEPTION 'APP: coupon_invalid | Kupon bu sepetteki mağazalar için geçerli değil'
          USING ERRCODE = 'P0001';
      END IF;
      IF v_coupon_by_shop ? v_c.shop_id::text THEN
        RAISE EXCEPTION 'APP: coupon_duplicate | Bir mağazaya yalnızca bir kupon uygulanabilir'
          USING ERRCODE = 'P0001';
      END IF;
      IF v_c.is_active IS NOT TRUE THEN
        RAISE EXCEPTION 'APP: coupon_inactive | "%" kuponu artık geçerli değil', v_c.code USING ERRCODE = 'P0001';
      END IF;
      IF v_c.start_date IS NOT NULL AND v_c.start_date > v_now THEN
        RAISE EXCEPTION 'APP: coupon_not_started | "%" kuponu henüz başlamadı', v_c.code USING ERRCODE = 'P0001';
      END IF;
      IF v_c.end_date IS NOT NULL AND v_c.end_date < v_now THEN
        RAISE EXCEPTION 'APP: coupon_expired | "%" kuponunun süresi dolmuş', v_c.code USING ERRCODE = 'P0001';
      END IF;
      IF v_c.usage_limit IS NOT NULL AND COALESCE(v_c.usage_count, 0) >= v_c.usage_limit THEN
        RAISE EXCEPTION 'APP: coupon_limit | "%" kuponunun kullanım limiti doldu', v_c.code USING ERRCODE = 'P0001';
      END IF;
      IF v_c.usage_per_user IS NOT NULL AND (
           SELECT count(*) FROM public.coupon_usages u
            WHERE u.coupon_id = v_cid AND u.user_id = v_user) >= v_c.usage_per_user THEN
        RAISE EXCEPTION 'APP: coupon_used | "%" kuponunu daha önce kullandınız', v_c.code USING ERRCODE = 'P0001';
      END IF;
      v_coupon_by_shop := v_coupon_by_shop || jsonb_build_object(v_c.shop_id::text, v_cid);
    END LOOP;
  END IF;

  -- 7) Mağaza başına döküm (CartProvider.getDeliveryFee ile aynı öncelik)
  FOREACH v_sid IN ARRAY v_shop_ids
  LOOP
    SELECT s.id, s.name, s.delivery_fee, s.free_delivery_min_amount,
           s.min_order_amount, s.commission_rate
      INTO v_shop
      FROM public.shops s WHERE s.id = v_sid;

    SELECT COALESCE(SUM((e->>'subtotal')::numeric), 0) INTO v_sub
      FROM jsonb_array_elements(v_items) AS e
     WHERE (e->>'shop_id')::uuid = v_sid;
    v_sub := round(v_sub, 2);

    IF COALESCE(v_shop.min_order_amount, 0) > 0 AND v_sub < v_shop.min_order_amount THEN
      v_msg := 'APP: min_order_amount | ' || COALESCE(v_shop.name, 'Dükkan') || chr(10)
        || 'Minimum sipariş tutarı: ₺' || to_char(v_shop.min_order_amount, 'FM999999990.00') || chr(10)
        || 'Mevcut tutar: ₺' || to_char(v_sub, 'FM999999990.00') || chr(10)
        || 'Eksik tutar: ₺' || to_char(v_shop.min_order_amount - v_sub, 'FM999999990.00');
      RAISE EXCEPTION '%', v_msg USING ERRCODE = 'P0001';
    END IF;

    v_is_pickup := v_sid = ANY(v_pickups);
    IF v_is_pickup THEN
      v_fee := 0;
    ELSE
      SELECT MAX(pp.shipping_fee), BOOL_AND(COALESCE(pp.free_shipping, false))
        INTO v_max_fee, v_all_free
        FROM jsonb_array_elements(v_items) AS e
        JOIN public.products pp ON pp.id = (e->>'product_id')::uuid
       WHERE (e->>'shop_id')::uuid = v_sid;
      IF COALESCE(v_all_free, false) THEN
        v_fee := 0;
      ELSIF COALESCE(v_shop.free_delivery_min_amount, 0) > 0
            AND v_sub >= v_shop.free_delivery_min_amount THEN
        v_fee := 0;
      ELSIF v_max_fee IS NOT NULL THEN
        v_fee := v_max_fee;
      ELSE
        v_fee := COALESCE(v_shop.delivery_fee, 15.0);
      END IF;
    END IF;
    v_fee := round(GREATEST(v_fee, 0), 2);

    -- Kupon indirimi (AppliedCoupon.discountFor ile aynı)
    v_disc := 0;
    v_cid := NULLIF(v_coupon_by_shop->>v_sid::text, '')::uuid;
    IF v_cid IS NOT NULL THEN
      SELECT c.code, c.discount_type::text AS discount_type, c.discount_value,
             c.maximum_discount_amount, c.minimum_order_amount
        INTO v_c
        FROM public.shop_coupons c WHERE c.id = v_cid;
      IF COALESCE(v_c.minimum_order_amount, 0) > 0 AND v_sub < v_c.minimum_order_amount THEN
        RAISE EXCEPTION 'APP: coupon_min_order | "%" kuponu için en az ₺% tutarında alışveriş gerekli',
          v_c.code, to_char(v_c.minimum_order_amount, 'FM999999990.00') USING ERRCODE = 'P0001';
      END IF;
      IF v_c.discount_type = 'percentage' THEN
        v_disc := v_sub * COALESCE(v_c.discount_value, 0) / 100.0;
        IF v_c.maximum_discount_amount IS NOT NULL AND v_disc > v_c.maximum_discount_amount THEN
          v_disc := v_c.maximum_discount_amount;
        END IF;
      ELSE
        v_disc := COALESCE(v_c.discount_value, 0);
      END IF;
      v_disc := round(LEAST(GREATEST(v_disc, 0), v_sub), 2);
    END IF;

    v_total := v_sub + v_fee - v_disc;

    -- Komisyon: calculate_order_commission ile aynı oran normalizasyonu
    v_rate := COALESCE(v_shop.commission_rate, 10);
    IF v_rate > 1 THEN
      v_rate := v_rate / 100;
    END IF;
    v_comm := round(v_sub * v_rate, 2);

    IF v_total <= 0 THEN
      v_free_count := v_free_count + 1;
    END IF;

    -- Eski akışın teslimat metni (tekli: tam adres; çoklu: "başlık - tam adres")
    v_addr_text := CASE
      WHEN v_is_pickup AND v_multi THEN 'Gel Al - Mağazadan Teslim'
      WHEN v_is_pickup THEN 'Gel Al - Mağazadan Teslim (' || COALESCE(v_shop.name, 'Dükkan') || ')'
      WHEN v_multi THEN COALESCE(v_address.title, 'Adres') || ' - ' || v_full_addr
      ELSE v_full_addr
    END;

    v_sub_orders := v_sub_orders || jsonb_build_array(jsonb_build_object(
      'shop_id',               v_sid,
      'shop_name',             v_shop.name,
      'subtotal',              v_sub,
      'delivery_fee',          v_fee,
      'coupon_id',             v_cid,
      'coupon_discount',       v_disc,
      'total',                 v_total,
      'commission_amount',     v_comm,
      'is_pickup',             v_is_pickup,
      'delivery_address_text', v_addr_text
    ));
    v_sub_subt  := v_sub_subt  || jsonb_build_object(v_sid::text, v_sub);
    v_sub_fees  := v_sub_fees  || jsonb_build_object(v_sid::text, v_fee);
    v_sub_discs := v_sub_discs || jsonb_build_object(v_sid::text, v_disc);
    v_t_sub  := v_t_sub + v_sub;
    v_t_fee  := v_t_fee + v_fee;
    v_t_disc := v_t_disc + v_disc;
    v_t_comm := v_t_comm + v_comm;
  END LOOP;

  -- 8) Ücretsiz (0 TL) sipariş: kullanıcı başına 1 (OrderService.freeOrderLimitPerUser)
  IF v_free_count > 0 THEN
    SELECT count(*) INTO v_prev_free
      FROM public.orders o
     WHERE o.user_id = v_user AND o.total = 0 AND o.status <> 'cancelled';
    IF v_prev_free + v_free_count > 1 THEN
      RAISE EXCEPTION 'APP: free_order_limit | Ücretsiz sipariş hakkınızı kullandınız. Bu üründen sadece 1 kez ücretsiz sipariş verebilirsiniz.'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF v_pm = 'online' AND v_t_sub + v_t_fee - v_t_disc <= 0 THEN
    RAISE EXCEPTION 'APP: online_zero_total | 0 TL tutarındaki sipariş online ödenemez' USING ERRCODE = 'P0001';
  END IF;

  v_addr_snap := jsonb_build_object(
    'id',            v_address.id,
    'title',         v_address.title,
    'full_name',     v_address.full_name,
    'phone',         v_address.phone,
    'address_line1', v_address.address_line1,
    'address_line2', v_address.address_line2,
    'district',      v_address.district,
    'city',          v_address.city,
    'postal_code',   v_address.postal_code,
    'latitude',      v_address.latitude,
    'longitude',     v_address.longitude,
    'full_address',  v_full_addr
  );

  -- 9) Oturum
  INSERT INTO private.server_checkout_sessions (
    id, user_id, idempotency_key, payment_method, currency,
    address_id, coupon_id, order_group_id,
    server_subtotal, server_delivery_fee, server_discount, server_coupon_discount,
    server_commission_amount, server_total,
    sub_order_subtotals, sub_order_delivery_fees, sub_order_coupon_discounts,
    sub_order_coupon_ids, pickup_shop_ids, sub_orders,
    items_snapshot, delivery_address_snapshot, expires_at, notes, invoice_data
  ) VALUES (
    v_session_id, v_user, p_idempotency_key, v_pm, 'TRY',
    p_address_id,
    CASE WHEN (SELECT count(*) FROM jsonb_object_keys(v_coupon_by_shop)) = 1
         THEN (SELECT value #>> '{}' FROM jsonb_each(v_coupon_by_shop) LIMIT 1)::uuid END,
    CASE WHEN v_multi THEN gen_random_uuid() END,
    v_t_sub, v_t_fee, 0, v_t_disc,
    v_t_comm, v_t_sub + v_t_fee - v_t_disc,
    v_sub_subt, v_sub_fees, v_sub_discs,
    v_coupon_by_shop, v_pickups, v_sub_orders,
    v_items, v_addr_snap, v_expires_at, NULLIF(btrim(COALESCE(p_notes, '')), ''), p_invoice_data
  );

  -- 10) Flaş rezervasyonları (fırsat başına tek satır; UNIQUE(session_id, sale_id))
  FOR v_sale, v_need IN SELECT key, value::integer FROM jsonb_each_text(v_flash_need)
  LOOP
    INSERT INTO private.flash_sale_reservations (
      sale_id, session_id, user_id, product_id, shop_id,
      quantity, unit_price, original_price, expires_at
    )
    SELECT fs.id, v_session_id, v_user, fs.product_id, fs.shop_id,
           v_need, GREATEST(fs.flash_price, 0.01), GREATEST(fs.original_price, 0.01), v_expires_at
      FROM public.flash_sales fs
     WHERE fs.id = v_sale::uuid;
  END LOOP;

  INSERT INTO private.server_checkout_audit (session_id, user_id, event_type, detail)
  VALUES (v_session_id, v_user, 'session_prepared', jsonb_build_object(
    'payment_method', v_pm,
    'item_count',     jsonb_array_length(v_items),
    'shop_count',     cardinality(v_shop_ids),
    'pickup_count',   cardinality(v_pickups),
    'subtotal',       v_t_sub,
    'total',          v_t_sub + v_t_fee - v_t_disc
  ));

  RETURN QUERY SELECT
    v_session_id, p_idempotency_key, v_pm, 'TRY'::text, 'pending'::text, v_expires_at,
    v_t_sub, v_t_fee, 0::numeric, v_t_disc, v_t_comm, v_t_sub + v_t_fee - v_t_disc,
    v_items, v_sub_orders, v_addr_snap, NULLIF(btrim(COALESCE(p_notes, '')), ''), v_warnings;
END;
$function$;

REVOKE ALL ON FUNCTION private.prepare_checkout_session(jsonb, uuid, text, text, uuid[], uuid[], text, jsonb)
  FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.prepare_checkout_session(
  p_items           jsonb,
  p_address_id      uuid,
  p_payment_method  text,
  p_idempotency_key text,
  p_coupon_id       uuid   DEFAULT NULL,
  p_coupon_code     text   DEFAULT NULL,
  p_notes           text   DEFAULT NULL,
  p_invoice_data    jsonb  DEFAULT NULL,
  p_order_group_id  uuid   DEFAULT NULL,
  p_coupon_ids      uuid[] DEFAULT NULL,
  p_pickup_shop_ids uuid[] DEFAULT NULL
)
RETURNS TABLE(
  session_id uuid, idempotency_key text, payment_method text, currency text,
  status text, expires_at timestamptz,
  server_subtotal numeric, server_delivery_fee numeric, server_discount numeric,
  server_coupon_discount numeric, server_commission_amount numeric, server_total numeric,
  items jsonb, sub_orders jsonb, delivery_address jsonb, notes text, warnings jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'prepare_checkout_session: not authenticated' USING ERRCODE = '28000';
  END IF;

  -- p_coupon_code / p_order_group_id eski imza uyumu için duruyor; kullanılmaz
  -- (kupon kimliği validate_coupon'dan gelir, grup kimliği sunucuda üretilir).
  RETURN QUERY
  SELECT * FROM private.prepare_checkout_session(
    p_items, p_address_id, p_payment_method, p_idempotency_key,
    CASE WHEN p_coupon_id IS NULL THEN p_coupon_ids
         ELSE array_append(COALESCE(p_coupon_ids, '{}'::uuid[]), p_coupon_id) END,
    p_pickup_shop_ids, p_notes, p_invoice_data
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.prepare_checkout_session(jsonb, uuid, text, text, uuid, text, text, jsonb, uuid, uuid[], uuid[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_checkout_session(jsonb, uuid, text, text, uuid, text, text, jsonb, uuid, uuid[], uuid[])
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Ortak sipariş oluşturucu: oturum dökümünü siparişe çevirir
--    (çağıran oturumu FOR UPDATE ile kilitlemiş ve doğrulamış olmalı)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.checkout_create_orders(
  p_session_id             uuid,
  p_order_payment_method   text,
  p_payment_status         text,
  p_strict                 boolean,
  p_notify_seller          boolean,
  p_payment_transaction_id uuid    DEFAULT NULL,
  p_iyzico_payment_id      text    DEFAULT NULL,
  p_iyzico_conversation_id text    DEFAULT NULL,
  p_price_mismatch         boolean DEFAULT false
)
RETURNS TABLE(order_id uuid, order_number text, shop_id uuid, order_total numeric, group_order_number text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
#variable_conflict use_column
DECLARE
  v_s           private.server_checkout_sessions%ROWTYPE;
  v_now         timestamptz := now();
  v_multi       boolean;
  v_group_id    uuid;
  v_group_no    text;
  v_sub         jsonb;
  v_it          jsonb;
  v_sid         uuid;
  v_cid         uuid;
  v_disc        numeric;
  v_order_id    uuid;
  v_order_no    text;
  v_order_total numeric;
  v_first_order uuid;
  v_c           record;
  v_r           record;
  v_owner       uuid;
  v_customer    text;
  v_claim       integer;
  v_take        integer;
  v_count       integer := 0;
BEGIN
  SELECT s.* INTO v_s FROM private.server_checkout_sessions s WHERE s.id = p_session_id;
  IF NOT FOUND OR v_s.sub_orders IS NULL OR jsonb_array_length(v_s.sub_orders) = 0 THEN
    RAISE EXCEPTION 'APP: session_invalid | Ödeme oturumu geçersiz, lütfen tekrar deneyin' USING ERRCODE = 'P0001';
  END IF;

  v_multi := jsonb_array_length(v_s.sub_orders) > 1;
  IF v_multi THEN
    v_group_id := COALESCE(v_s.order_group_id, gen_random_uuid());
    v_group_no := 'GRP' || floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint::text;
  END IF;

  SELECT COALESCE(NULLIF(p.full_name, ''), NULLIF(p.username, '')) INTO v_customer
    FROM public.profiles p WHERE p.id = v_s.user_id;
  v_customer := COALESCE(v_customer, 'Müşteri');

  FOR v_sub IN SELECT e FROM jsonb_array_elements(v_s.sub_orders) AS e
  LOOP
    v_sid  := (v_sub->>'shop_id')::uuid;
    v_cid  := NULLIF(v_sub->>'coupon_id', '')::uuid;
    v_disc := COALESCE((v_sub->>'coupon_discount')::numeric, 0);
    v_order_no := 'ORD' || lpad(nextval('public.order_number_seq')::text, 8, '0');

    -- discount = coupon_discount = kupon tutarı (20261016000010 sözleşmesi;
    -- uygulama indirim satırını orders.discount'tan gösterir).
    INSERT INTO public.orders (
      order_number, user_id, shop_id, order_group_id, group_order_number,
      delivery_address_text, address_id, customer_phone,
      payment_method, payment_status, status,
      subtotal, delivery_fee, discount, coupon_id, coupon_discount, total,
      is_pickup, notes, checkout_session_id, committed_at,
      payment_transaction_id, iyzico_payment_id, iyzico_conversation_id, price_mismatch,
      invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no,
      invoice_tax_office, invoice_address, invoice_email
    ) VALUES (
      v_order_no, v_s.user_id, v_sid, v_group_id::text, v_group_no,
      v_sub->>'delivery_address_text', v_s.address_id, v_s.delivery_address_snapshot->>'phone',
      p_order_payment_method::public.payment_method,
      p_payment_status::public.payment_status,
      'pending'::public.order_status,
      (v_sub->>'subtotal')::numeric, (v_sub->>'delivery_fee')::numeric, v_disc,
      v_cid, v_disc, (v_sub->>'total')::numeric,
      COALESCE((v_sub->>'is_pickup')::boolean, false), v_s.notes, v_s.id, v_now,
      p_payment_transaction_id, p_iyzico_payment_id, p_iyzico_conversation_id,
      COALESCE(p_price_mismatch, false),
      v_s.invoice_data->>'invoice_type',
      v_s.invoice_data->>'invoice_full_name',
      v_s.invoice_data->>'invoice_tax_number',
      v_s.invoice_data->>'invoice_tc_no',
      v_s.invoice_data->>'invoice_tax_office',
      v_s.invoice_data->>'invoice_address',
      v_s.invoice_data->>'invoice_email'
    )
    RETURNING id INTO v_order_id;

    FOR v_it IN
      SELECT e FROM jsonb_array_elements(v_s.items_snapshot) AS e
       WHERE (e->>'shop_id')::uuid = v_sid
    LOOP
      INSERT INTO public.order_items (
        order_id, product_id, product_name, price, product_price, quantity, subtotal,
        product_image_url, shop_id, shop_name, flash_sale_id, flash_price
      ) VALUES (
        v_order_id,
        (v_it->>'product_id')::uuid,
        COALESCE(v_it->>'product_name', 'Ürün'),
        (v_it->>'unit_price')::numeric,
        (v_it->>'unit_price')::numeric,
        (v_it->>'quantity')::integer,
        (v_it->>'subtotal')::numeric,
        v_it->>'image_url',
        v_sid,
        v_it->>'shop_name',
        NULLIF(v_it->>'flash_sale_id', '')::uuid,
        NULLIF(v_it->>'flash_price', '')::numeric
      );
    END LOOP;

    -- Kupon kullanımı (eski akışta use_coupon RPC'si)
    IF v_cid IS NOT NULL AND v_disc > 0 THEN
      SELECT c.code, c.is_active, c.usage_limit, c.usage_count, c.usage_per_user INTO v_c
        FROM public.shop_coupons c WHERE c.id = v_cid FOR UPDATE;
      IF p_strict AND (
           v_c.is_active IS NOT TRUE
           OR (v_c.usage_limit IS NOT NULL AND COALESCE(v_c.usage_count, 0) >= v_c.usage_limit)
           OR (v_c.usage_per_user IS NOT NULL AND (
                 SELECT count(*) FROM public.coupon_usages u
                  WHERE u.coupon_id = v_cid AND u.user_id = v_s.user_id) >= v_c.usage_per_user)
         ) THEN
        RAISE EXCEPTION 'APP: coupon_invalid | "%" kuponu artık kullanılamıyor', v_c.code USING ERRCODE = 'P0001';
      END IF;
      INSERT INTO public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
      VALUES (v_cid, v_order_id, v_s.user_id, v_disc);
      UPDATE public.shop_coupons c
         SET usage_count = COALESCE(c.usage_count, 0) + 1
       WHERE c.id = v_cid;
    END IF;

    -- "2 al biri bakiye" kampanyası (eski akışta istemci çağırıyordu)
    BEGIN
      PERFORM public.apply_campaign_rewards_for_order(v_order_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE LOG 'checkout: apply_campaign_rewards_for_order % failed: %', v_order_id, SQLERRM;
    END;

    SELECT o.total INTO v_order_total FROM public.orders o WHERE o.id = v_order_id;

    -- Satıcıya "Yeni Sipariş!" (eski akışta OrderService.createOrder gönderiyordu)
    IF p_notify_seller THEN
      BEGIN
        SELECT s.owner_id INTO v_owner FROM public.shops s WHERE s.id = v_sid;
        IF v_owner IS NOT NULL AND v_owner <> v_s.user_id
           AND NOT EXISTS (
             SELECT 1 FROM public.notification_preferences np
              WHERE np.user_id = v_owner AND np.order_updates_enabled IS FALSE) THEN
          PERFORM public.add_notification(
            v_owner, 'new_order', 'Yeni Sipariş!',
            v_customer || ' - ₺' || to_char(v_order_total, 'FM999999990.00')
              || ' tutarında yeni sipariş geldi!',
            v_s.user_id, v_customer, NULL, v_order_id::text, NULL);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE LOG 'checkout: seller notification for % failed: %', v_order_id, SQLERRM;
      END;
    END IF;

    IF v_first_order IS NULL THEN
      v_first_order := v_order_id;
    END IF;
    v_count := v_count + 1;

    order_id           := v_order_id;
    order_number       := v_order_no;
    shop_id            := v_sid;
    order_total        := v_order_total;
    group_order_number := v_group_no;
    RETURN NEXT;
  END LOOP;

  -- Flaş: rezervasyon satışa döner; sepetteki talep tüketilir
  FOR v_r IN
    SELECT r.* FROM private.flash_sale_reservations r
     WHERE r.session_id = v_s.id AND r.status = 'active'
     FOR UPDATE
  LOOP
    PERFORM 1 FROM public.flash_sales fs WHERE fs.id = v_r.sale_id FOR UPDATE;
    SELECT c.quantity INTO v_claim
      FROM private.flash_sale_claims c
     WHERE c.user_id = v_s.user_id AND c.sale_id = v_r.sale_id
     FOR UPDATE;
    v_take := LEAST(COALESCE(v_claim, 0), v_r.quantity);
    IF v_take > 0 THEN
      UPDATE private.flash_sale_claims c
         SET quantity = c.quantity - v_take, updated_at = v_now
       WHERE c.user_id = v_s.user_id AND c.sale_id = v_r.sale_id;
    END IF;
    IF v_r.quantity > v_take THEN
      UPDATE public.flash_sales fs
         SET sold_count = LEAST(fs.stock_limit, fs.sold_count + (v_r.quantity - v_take))
       WHERE fs.id = v_r.sale_id;
    END IF;
    UPDATE private.flash_sale_reservations r
       SET status = 'committed', committed_at = v_now, updated_at = v_now
     WHERE r.id = v_r.id;
  END LOOP;

  UPDATE private.server_checkout_sessions s
     SET status                 = 'committed',
         committed_at           = v_now,
         order_id               = v_first_order,
         order_group_order_id   = v_group_id,
         payment_transaction_id = COALESCE(p_payment_transaction_id, s.payment_transaction_id),
         updated_at             = v_now
   WHERE s.id = v_s.id;

  INSERT INTO private.server_checkout_audit (session_id, payment_transaction_id, user_id, event_type, detail)
  VALUES (v_s.id, p_payment_transaction_id, v_s.user_id, 'session_committed', jsonb_build_object(
    'order_id',       v_first_order,
    'order_group_id', v_group_id,
    'order_count',    v_count,
    'total',          v_s.server_total,
    'payment_method', p_order_payment_method
  ));
END;
$function$;

REVOKE ALL ON FUNCTION private.checkout_create_orders(uuid, text, text, boolean, boolean, uuid, text, text, boolean)
  FROM PUBLIC, anon, authenticated;

-- Kilitli + doğrulanmış oturumu (kapıda / bakiye) döndüren ortak kontrol
CREATE OR REPLACE FUNCTION private.checkout_lock_session_for_commit(p_session_id uuid, p_methods text[])
RETURNS private.server_checkout_sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_s    private.server_checkout_sessions%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication gerekli' USING ERRCODE = '42501';
  END IF;

  SELECT s.* INTO v_s FROM private.server_checkout_sessions s WHERE s.id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP: session_not_found | Ödeme oturumu bulunamadı, lütfen tekrar deneyin' USING ERRCODE = 'P0001';
  END IF;
  IF v_s.user_id <> v_user THEN
    RAISE EXCEPTION 'Bu oturum bu kullaniciya ait degil' USING ERRCODE = '42501';
  END IF;
  IF v_s.status = 'committed' THEN
    RETURN v_s;  -- çağıran idempotent yanıt döner
  END IF;
  IF v_s.status <> 'pending' THEN
    RAISE EXCEPTION 'APP: session_closed | Ödeme oturumu kapandı, lütfen tekrar deneyin' USING ERRCODE = 'P0001';
  END IF;
  IF v_s.expires_at < now() THEN
    RAISE EXCEPTION 'APP: session_expired | Ödeme oturumunun süresi doldu, lütfen tekrar deneyin' USING ERRCODE = 'P0001';
  END IF;
  IF NOT (v_s.payment_method = ANY(p_methods)) THEN
    RAISE EXCEPTION 'Bu RPC bu odeme yontemi icin degil: %', v_s.payment_method USING ERRCODE = 'P0001';
  END IF;
  RETURN v_s;
END;
$function$;

REVOKE ALL ON FUNCTION private.checkout_lock_session_for_commit(uuid, text[]) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) commit_cod_order / commit_balance_order (dönüş değişti → DROP + CREATE)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.commit_cod_order(uuid);
DROP FUNCTION IF EXISTS public.commit_balance_order(uuid);
DROP FUNCTION IF EXISTS private.commit_cod_order(uuid);
DROP FUNCTION IF EXISTS private.commit_balance_order(uuid);

CREATE FUNCTION private.commit_cod_order(p_session_id uuid)
RETURNS TABLE(
  order_id uuid, order_number text, order_group_id uuid, status text, total numeric,
  order_count integer, group_order_number text, order_ids uuid[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
#variable_conflict use_column
DECLARE
  v_s     private.server_checkout_sessions%ROWTYPE;
  v_o     record;
  v_ids   uuid[] := '{}';
  v_first uuid;
  v_no    text;
  v_grp   text;
  v_sum   numeric := 0;
BEGIN
  v_s := private.checkout_lock_session_for_commit(p_session_id, ARRAY['cash', 'card_on_delivery']);

  IF v_s.status = 'committed' THEN
    RETURN QUERY
    SELECT (array_agg(o.id ORDER BY o.created_at, o.order_number))[1],
           (array_agg(o.order_number ORDER BY o.created_at, o.order_number))[1],
           v_s.order_group_order_id, 'committed'::text, COALESCE(SUM(o.total), 0),
           count(*)::integer, max(o.group_order_number),
           array_agg(o.id ORDER BY o.created_at, o.order_number)
      FROM public.orders o WHERE o.checkout_session_id = v_s.id;
    RETURN;
  END IF;

  FOR v_o IN
    SELECT * FROM private.checkout_create_orders(
      v_s.id,
      CASE v_s.payment_method WHEN 'card_on_delivery' THEN 'cardOnDelivery' ELSE 'cash' END,
      'pending', true, true)
  LOOP
    v_ids := v_ids || v_o.order_id;
    IF v_first IS NULL THEN
      v_first := v_o.order_id;
      v_no := v_o.order_number;
    END IF;
    v_grp := v_o.group_order_number;
    v_sum := v_sum + COALESCE(v_o.order_total, 0);
  END LOOP;

  RETURN QUERY SELECT
    v_first, v_no,
    (SELECT s.order_group_order_id FROM private.server_checkout_sessions s WHERE s.id = v_s.id),
    'committed'::text, v_sum, cardinality(v_ids), v_grp, v_ids;
END;
$function$;

CREATE FUNCTION private.commit_balance_order(p_session_id uuid)
RETURNS TABLE(
  order_id uuid, order_number text, order_group_id uuid, status text, total numeric,
  order_count integer, group_order_number text, order_ids uuid[],
  balance_transaction_id uuid, new_balance numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
#variable_conflict use_column
DECLARE
  v_s       private.server_checkout_sessions%ROWTYPE;
  v_o       record;
  v_pay     record;
  v_balance numeric;
  v_ids     uuid[] := '{}';
  v_first   uuid;
  v_no      text;
  v_grp     text;
  v_sum     numeric := 0;
  v_txn     uuid;
  v_new_bal numeric;
BEGIN
  v_s := private.checkout_lock_session_for_commit(p_session_id, ARRAY['balance']);

  IF v_s.status = 'committed' THEN
    RETURN QUERY
    SELECT (array_agg(o.id ORDER BY o.created_at, o.order_number))[1],
           (array_agg(o.order_number ORDER BY o.created_at, o.order_number))[1],
           v_s.order_group_order_id, 'committed'::text, COALESCE(SUM(o.total), 0),
           count(*)::integer, max(o.group_order_number),
           array_agg(o.id ORDER BY o.created_at, o.order_number),
           NULL::uuid,
           (SELECT ub.balance FROM public.user_balances ub WHERE ub.user_id = v_s.user_id)
      FROM public.orders o WHERE o.checkout_session_id = v_s.id;
    RETURN;
  END IF;

  -- Hepsi ya da hiçbiri: toplam bakiye yetmezse hiçbir sipariş açılmaz
  SELECT ub.balance INTO v_balance
    FROM public.user_balances ub WHERE ub.user_id = v_s.user_id FOR UPDATE;
  IF COALESCE(v_balance, 0) < v_s.server_total THEN
    RAISE EXCEPTION 'APP: insufficient_balance | Yetersiz bakiye! Mevcut: ₺%, Gerekli: ₺%',
      to_char(COALESCE(v_balance, 0), 'FM999999990.00'),
      to_char(v_s.server_total, 'FM999999990.00') USING ERRCODE = 'P0001';
  END IF;

  FOR v_o IN
    SELECT * FROM private.checkout_create_orders(v_s.id, 'balance', 'pending', true, true)
  LOOP
    v_ids := v_ids || v_o.order_id;
    IF v_first IS NULL THEN
      v_first := v_o.order_id;
      v_no := v_o.order_number;
    END IF;
    v_grp := v_o.group_order_number;
    v_sum := v_sum + COALESCE(v_o.order_total, 0);
  END LOOP;

  -- Eski akışla aynı defter kaydı (reference_type='order', reference_id=sipariş)
  FOR v_o IN
    SELECT o.id, o.total FROM public.orders o
     WHERE o.id = ANY(v_ids) ORDER BY o.created_at, o.order_number
  LOOP
    IF COALESCE(v_o.total, 0) > 0 THEN
      SELECT u.transaction_id, u.new_balance INTO v_pay
        FROM public.use_balance_for_order(v_o.id) AS u;
      v_txn := v_pay.transaction_id;
      v_new_bal := v_pay.new_balance;
    ELSE
      UPDATE public.orders o SET payment_status = 'paid', updated_at = now() WHERE o.id = v_o.id;
    END IF;
  END LOOP;

  IF v_new_bal IS NULL THEN
    SELECT ub.balance INTO v_new_bal FROM public.user_balances ub WHERE ub.user_id = v_s.user_id;
  END IF;

  RETURN QUERY SELECT
    v_first, v_no,
    (SELECT s.order_group_order_id FROM private.server_checkout_sessions s WHERE s.id = v_s.id),
    'committed'::text, v_sum, cardinality(v_ids), v_grp, v_ids, v_txn, v_new_bal;
END;
$function$;

REVOKE ALL ON FUNCTION private.commit_cod_order(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.commit_balance_order(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.commit_cod_order(p_session_id uuid)
RETURNS TABLE(
  order_id uuid, order_number text, order_group_id uuid, status text, total numeric,
  order_count integer, group_order_number text, order_ids uuid[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'commit_cod_order: not authenticated' USING ERRCODE = '28000';
  END IF;
  RETURN QUERY SELECT * FROM private.commit_cod_order(p_session_id);
END;
$function$;

CREATE FUNCTION public.commit_balance_order(p_session_id uuid)
RETURNS TABLE(
  order_id uuid, order_number text, order_group_id uuid, status text, total numeric,
  order_count integer, group_order_number text, order_ids uuid[],
  balance_transaction_id uuid, new_balance numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'commit_balance_order: not authenticated' USING ERRCODE = '28000';
  END IF;
  RETURN QUERY SELECT * FROM private.commit_balance_order(p_session_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.commit_cod_order(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.commit_balance_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.commit_cod_order(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.commit_balance_order(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Kullanıcı onay penceresini kapatınca: oturum + flaş rezervasyonu bırakılır
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_checkout_session(p_session_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_rows integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'cancel_checkout_session: not authenticated' USING ERRCODE = '28000';
  END IF;

  -- Ödeme sayfası açılmış online oturuma dokunulmaz (geri çağrı gelebilir).
  UPDATE private.server_checkout_sessions s
     SET status = 'cancelled', cancelled_at = now(),
         cancellation_reason = 'user_cancelled', updated_at = now()
   WHERE s.id = p_session_id AND s.user_id = v_user
     AND s.status = 'pending' AND s.payment_transaction_id IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows > 0 THEN
    UPDATE private.flash_sale_reservations r
       SET status = 'released', released_at = now(),
           release_reason = 'session_cancelled', updated_at = now()
     WHERE r.session_id = p_session_id AND r.status = 'active';

    INSERT INTO private.server_checkout_audit (session_id, user_id, event_type, detail)
    VALUES (p_session_id, v_user, 'session_cancelled', jsonb_build_object('reason', 'user_cancelled'));
  END IF;

  RETURN v_rows > 0;
END;
$function$;

REVOKE ALL ON FUNCTION public.cancel_checkout_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_checkout_session(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) Online: iyzico geri çağrısı → complete_online_payment → oturumdan sipariş
-- ---------------------------------------------------------------------------
-- Ödeme başlatma Edge Function'ı oturum verisini okur (sipariş dökümü dahil).
DROP FUNCTION IF EXISTS public.get_checkout_session_for_payment(uuid, uuid);
CREATE FUNCTION public.get_checkout_session_for_payment(p_session_id uuid, p_user_id uuid)
RETURNS TABLE(
  id uuid, user_id uuid, status text, payment_method text, expires_at timestamptz,
  address_id uuid, items_snapshot jsonb, delivery_address_snapshot jsonb,
  server_total numeric, server_delivery_fee numeric, expected_paid_price numeric,
  server_subtotal numeric, server_coupon_discount numeric, sub_orders jsonb,
  notes text, payment_transaction_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT s.id, s.user_id, s.status, s.payment_method, s.expires_at,
         s.address_id, s.items_snapshot, s.delivery_address_snapshot,
         s.server_total, s.server_delivery_fee, s.expected_paid_price,
         s.server_subtotal, s.server_coupon_discount, s.sub_orders,
         s.notes, s.payment_transaction_id
    FROM private.server_checkout_sessions s
   WHERE s.id = p_session_id
     AND s.user_id = p_user_id;
$function$;

REVOKE ALL ON FUNCTION public.get_checkout_session_for_payment(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_checkout_session_for_payment(uuid, uuid) TO service_role;

-- Var olan (hiç çağrılmamış) commit_online_order aynı ortak oluşturucuya bağlanır.
-- Para alınmış olduğundan tutar/para birimi farkı siparişi engellemez:
-- sipariş price_mismatch=true ile açılır ve denetim kaydı düşülür (taksit
-- vade farkı iyzico paidPrice'ı toplamın üstüne çıkarabilir; o fark değildir).
CREATE OR REPLACE FUNCTION public.commit_online_order(p_payment_transaction_id uuid)
RETURNS TABLE(order_id uuid, order_group_id uuid, order_number text, status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
#variable_conflict use_column
DECLARE
  v_pt       public.payment_transactions%ROWTYPE;
  v_s        private.server_checkout_sessions%ROWTYPE;
  v_sid      uuid;
  v_o        record;
  v_first    uuid;
  v_no       text;
  v_mismatch boolean := false;
BEGIN
  SELECT pt.* INTO v_pt FROM public.payment_transactions pt
   WHERE pt.id = p_payment_transaction_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment transaction bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  IF v_pt.order_id IS NOT NULL THEN
    -- Eski çoklu siparişlerin grup kimliği 'GRP_<ms>' metnidir, uuid değil.
    RETURN QUERY SELECT o.id,
           CASE WHEN o.order_group_id ~* '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
                THEN o.order_group_id::uuid END,
           o.order_number, 'committed'::text
      FROM public.orders o WHERE o.id = v_pt.order_id;
    RETURN;
  END IF;

  IF v_pt.payment_status IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'Order olusturulamaz: payment_status=% (yalnizca success izinli)',
      v_pt.payment_status USING ERRCODE = 'P0001';
  END IF;

  v_sid := COALESCE(v_pt.checkout_session_id,
                    NULLIF(v_pt.callback_data->>'checkout_session_id', '')::uuid);
  IF v_sid IS NULL THEN
    RAISE EXCEPTION 'payment_transactions.checkout_session_id NULL' USING ERRCODE = 'P0001';
  END IF;

  SELECT s.* INTO v_s FROM private.server_checkout_sessions s WHERE s.id = v_sid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session bulunamadi' USING ERRCODE = 'P0002';
  END IF;
  IF v_s.user_id IS DISTINCT FROM v_pt.user_id THEN
    RAISE EXCEPTION 'Session user_id ile payment user_id uyumsuz' USING ERRCODE = '42501';
  END IF;
  IF v_s.payment_method <> 'online' THEN
    RAISE EXCEPTION 'Oturum online odeme icin degil: %', v_s.payment_method USING ERRCODE = 'P0001';
  END IF;

  IF v_s.status = 'committed' THEN
    UPDATE public.payment_transactions pt
       SET order_id = v_s.order_id, updated_at = now()
     WHERE pt.id = p_payment_transaction_id AND pt.order_id IS NULL;
    RETURN QUERY SELECT o.id, v_s.order_group_order_id, o.order_number, 'committed'::text
      FROM public.orders o WHERE o.id = v_s.order_id;
    RETURN;
  END IF;

  IF (v_pt.paid_price IS NOT NULL AND v_pt.paid_price < v_s.server_total - 0.01)
     OR (v_pt.currency IS NOT NULL AND upper(v_pt.currency) <> 'TRY') THEN
    v_mismatch := true;
    INSERT INTO private.server_checkout_audit (session_id, payment_transaction_id, user_id, event_type, detail)
    VALUES (v_s.id, p_payment_transaction_id, v_s.user_id, 'amount_mismatch', jsonb_build_object(
      'server_total', v_s.server_total, 'paid_price', v_pt.paid_price, 'currency', v_pt.currency));
  END IF;

  -- Süresi dolmuş olsa bile: para alındı, sipariş açılmalı.
  FOR v_o IN
    SELECT * FROM private.checkout_create_orders(
      v_s.id, 'online', 'paid', false, false,
      p_payment_transaction_id, v_pt.payment_id, v_pt.conversation_id, v_mismatch)
  LOOP
    IF v_first IS NULL THEN
      v_first := v_o.order_id;
      v_no := v_o.order_number;
    END IF;
  END LOOP;

  UPDATE public.payment_transactions pt
     SET order_id = v_first, checkout_session_id = v_s.id, updated_at = now()
   WHERE pt.id = p_payment_transaction_id AND pt.order_id IS NULL;

  RETURN QUERY SELECT
    v_first,
    (SELECT s.order_group_order_id FROM private.server_checkout_sessions s WHERE s.id = v_s.id),
    v_no, 'committed'::text;
END;
$function$;

REVOKE ALL ON FUNCTION public.commit_online_order(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_online_order(uuid) TO service_role;

-- complete_online_payment: oturumlu ödeme dalı eklendi; eski (order_data) dal
-- canlı tanımla birebir aynı.
CREATE OR REPLACE FUNCTION public.complete_online_payment(p_payment_transaction_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_payment_record RECORD;
  v_order_data JSONB;
  v_user_id UUID;
  v_shop_id UUID;
  v_order_id UUID;
  v_order_number VARCHAR;
  v_item JSONB;
  v_items JSONB;
  v_total DECIMAL;
  v_subtotal DECIMAL;
  v_delivery_fee DECIMAL;
  v_coupon_discount DECIMAL;
  v_coupon_id UUID;
  v_delivery_address_text TEXT;
  v_delivery_address_id UUID;
  v_note TEXT;
  v_customer_phone TEXT;
  v_shop_name TEXT;
  v_existing_order_id UUID;
BEGIN
  -- IDEMPOTENT: Önce bu transaction için zaten oluşturulmuş order var mı?
  SELECT order_id INTO v_existing_order_id
  FROM public.payment_transactions
  WHERE id = p_payment_transaction_id;

  IF v_existing_order_id IS NOT NULL THEN
    RAISE NOTICE 'Sipariş zaten oluşturulmuş (idempotent): order_id=%', v_existing_order_id;
    RETURN v_existing_order_id;
  END IF;

  -- 1. Payment transaction'ı al
  SELECT * INTO v_payment_record
  FROM public.payment_transactions
  WHERE id = p_payment_transaction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment transaction bulunamadı: %', p_payment_transaction_id;
  END IF;

  IF v_payment_record.payment_status = 'failure' THEN
    RAISE EXCEPTION 'Başarısız ödeme için sipariş oluşturulamaz: %', p_payment_transaction_id;
  END IF;

  -- 1b. Sunucu-otoriteli oturum (2026-10-17): sipariş(ler) oturum dökümünden
  IF v_payment_record.checkout_session_id IS NOT NULL
     OR NULLIF(v_payment_record.callback_data ->> 'checkout_session_id', '') IS NOT NULL THEN
    SELECT c.order_id INTO v_order_id
      FROM public.commit_online_order(p_payment_transaction_id) AS c;
    RETURN v_order_id;
  END IF;

  -- 2. Callback data'dan sipariş bilgilerini çıkar
  v_order_data := v_payment_record.callback_data -> 'order_data';
  v_user_id := (v_payment_record.callback_data ->> 'user_id')::UUID;

  IF v_order_data IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sipariş verileri eksik (callback_data). callback_data: %', v_payment_record.callback_data;
  END IF;

  v_shop_id := (v_order_data ->> 'shop_id')::UUID;
  v_total := (v_order_data ->> 'total')::DECIMAL;
  v_subtotal := (v_order_data ->> 'subtotal')::DECIMAL;
  v_delivery_fee := COALESCE((v_order_data ->> 'delivery_fee')::DECIMAL, 0);
  v_coupon_discount := COALESCE((v_order_data ->> 'coupon_discount')::DECIMAL, 0);
  -- coupon_id opsiyonel: boş string/null/eksik ise NULL bırak (kupon yok).
  -- NULLIF(..., '') boş string'i de yakalar; aksi halde ''::UUID exception fırlatır.
  v_coupon_id := NULLIF(v_order_data ->> 'coupon_id', '')::UUID;
  v_delivery_address_text := v_order_data ->> 'delivery_address_text';
  v_note := v_order_data ->> 'note';
  v_items := v_order_data -> 'items';
  v_customer_phone := v_order_data ->> 'customer_phone';

  SELECT name INTO v_shop_name FROM public.shops WHERE id = v_shop_id;

  IF v_order_data ->> 'delivery_address_id' IS NOT NULL AND v_order_data ->> 'delivery_address_id' != '' THEN
    v_delivery_address_id := (v_order_data ->> 'delivery_address_id')::UUID;
  END IF;

  -- 3. Sipariş numarası oluştur
  v_order_number := 'ONL-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' ||
                    LPAD(FLOOR(RANDOM() * 99999)::TEXT, 5, '0');

  -- 4. Siparişi oluştur (coupon_id artık dahil)
  INSERT INTO public.orders (
    user_id,
    shop_id,
    order_number,
    status,
    payment_method,
    payment_status,
    total,
    subtotal,
    delivery_fee,
    discount,
    coupon_id,
    coupon_discount,
    delivery_address_text,
    delivery_address_id,
    notes,
    customer_phone,
    payment_transaction_id,
    iyzico_payment_id,
    iyzico_conversation_id
  ) VALUES (
    v_user_id,
    v_shop_id,
    v_order_number,
    'pending',
    'online',
    'paid',
    v_total,
    v_subtotal,
    v_delivery_fee,
    v_coupon_discount,
    v_coupon_id,
    v_coupon_discount,
    v_delivery_address_text,
    v_delivery_address_id,
    v_note,
    v_customer_phone,
    p_payment_transaction_id,
    v_payment_record.payment_id,
    v_payment_record.conversation_id
  )
  RETURNING id INTO v_order_id;

  -- 5. Sipariş kalemlerini oluştur
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items)
  LOOP
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price,
      product_price,
      subtotal,
      shop_id,
      shop_name
    ) VALUES (
      v_order_id,
      (v_item ->> 'product_id')::UUID,
      v_item ->> 'product_name',
      (v_item ->> 'quantity')::INTEGER,
      (v_item ->> 'price')::DECIMAL,
      (v_item ->> 'price')::DECIMAL,
      (v_item ->> 'price')::DECIMAL * (v_item ->> 'quantity')::INTEGER,
      v_shop_id,
      v_shop_name
    );
  END LOOP;

  -- 6. Payment transaction'a order_id'yi bağla (race condition koruması)
  UPDATE public.payment_transactions
  SET order_id = v_order_id,
      updated_at = NOW()
  WHERE id = p_payment_transaction_id
    AND order_id IS NULL;

  RAISE NOTICE 'Online sipariş oluşturuldu: order_id=%, order_number=%, coupon_id=%', v_order_id, v_order_number, v_coupon_id;

  RETURN v_order_id;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 6) resync_order_totals: kupon bir kez düşülür
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.resync_order_totals()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_order_id  uuid := COALESCE(NEW.order_id, OLD.order_id);
  v_subtotal  numeric;
  v_order     record;
  v_discount  numeric;
  v_coupon    numeric;
  v_total     numeric;
BEGIN
  SELECT o.* INTO v_order FROM public.orders o WHERE o.id = v_order_id;
  IF NOT FOUND OR v_order.status IS DISTINCT FROM 'pending'::public.order_status THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  SELECT COALESCE(SUM(oi.subtotal), 0)
    INTO v_subtotal
    FROM public.order_items oi
   WHERE oi.order_id = v_order_id;

  -- discount ile coupon_discount AYNI kupon tutarını taşır (yazan her yol:
  -- eski istemci, complete_online_payment, oturum akışı). Toplamdan bir kez
  -- düşülür; ikisi de ara toplamı aşamaz.
  v_discount := LEAST(GREATEST(COALESCE(v_order.discount, 0), 0), v_subtotal);
  v_coupon   := LEAST(GREATEST(COALESCE(v_order.coupon_discount, 0), 0), v_subtotal);
  v_total    := ROUND(GREATEST(
                  v_subtotal + GREATEST(COALESCE(v_order.delivery_fee, 0), 0)
                  - GREATEST(v_discount, v_coupon), 0), 2);

  IF ABS(COALESCE(v_order.subtotal, 0) - v_subtotal) > 0.01
     OR ABS(COALESCE(v_order.total, 0) - v_total) > 0.01
     OR COALESCE(v_order.discount, 0) <> v_discount
     OR COALESCE(v_order.coupon_discount, 0) <> v_coupon
  THEN
    UPDATE public.orders
       SET subtotal        = v_subtotal,
           discount        = v_discount,
           coupon_discount = v_coupon,
           total           = v_total,
           updated_at      = NOW()
     WHERE id = v_order_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 7) Oturumlu sipariş iptal edilirse flaş adetleri geri verilir
--    (eski akışın talep geri yazımı checkout_session_id dolu siparişleri atlar)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.release_session_flash_on_order_cancel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NEW.status = 'cancelled'
     AND OLD.status IS DISTINCT FROM 'cancelled'
     AND NEW.checkout_session_id IS NOT NULL THEN
    UPDATE public.flash_sales f
       SET sold_count = GREATEST(0, f.sold_count - x.q)
      FROM (
        SELECT oi.flash_sale_id, SUM(oi.quantity)::integer AS q
          FROM public.order_items oi
         WHERE oi.order_id = NEW.id AND oi.flash_sale_id IS NOT NULL
         GROUP BY oi.flash_sale_id
      ) x
     WHERE f.id = x.flash_sale_id;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.release_session_flash_on_order_cancel() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_orders_release_session_flash_on_cancel ON public.orders;
CREATE TRIGGER trg_orders_release_session_flash_on_cancel
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION private.release_session_flash_on_order_cancel();

COMMIT;

NOTIFY pgrst, 'reload schema';

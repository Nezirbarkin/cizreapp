-- ============================================================================
-- 2026-08-19 | private.prepare_checkout_session: calistirilamaz hale getiren
--              MEVCUT hatalarin duzeltilmesi
-- ============================================================================
-- Bu hatalar bu tarihteki satici-paneli calismasindan ONCE de vardi; fonksiyon
-- her cagrildiginda ilk item islenmeden hata veriyordu. Aktif odeme ekranlari
-- (features/shop/services/order_service.dart) bu RPC'yi kullanmadigi icin
-- uretimde fark edilmemis. Yeni eklenen urun bazli kargo ve min/max siparis
-- adedi dogrulamasi bu fonksiyonun icinde calistigi icin once bunlar duzeltildi.
--
-- Duzeltilenler:
--
--  1) `s.deleted_at AS shop_deleted_at`
--     public.shops tablosunda deleted_at KOLONU YOK -> her cagrida
--     "42703 column s.deleted_at does not exist". Kolon uydurmak yerine
--     NULL::TIMESTAMPTZ konuldu; asagidaki
--     `IF ... OR v_product.shop_deleted_at IS NOT NULL` kontrolu boylece
--     her zaman "silinmemis" sonucu verir - yani kolonun hic olmadigi
--     durumdaki davranisin aynisi. Ileride gercek bir soft-delete kolonu
--     eklenirse burasi tekrar `s.deleted_at` yapilmalidir.
--
--  2) OUT parametresi / kolon adi cakismalari (42702 "column reference ...
--     is ambiguous"). Fonksiyon RETURNS TABLE(...) kullandigi icin
--     `idempotency_key`, `status`, `expires_at`, `session_id` ayni zamanda
--     birer PL/pgSQL degiskenidir; SQL ifadelerinde niteliksiz kullanilinca
--     PostgreSQL kolon mu degisken mi oldugunu secemiyor. Ilgili sorgulara
--     tablo alias'i (scs / fsr) eklenip referanslar nitelendirildi.
--
-- Sorgu MANTIGI degistirilmedi - flash_sale_reservations UPDATE'indeki
-- `session_id = gen_random_uuid()` placeholder kosulu (hicbir satiri
-- eslemez) bilerek oldugu gibi birakildi; onu degistirmek davranis
-- degisikligi olurdu ve bu migration'in kapsami disindadir.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION private.prepare_checkout_session(p_items jsonb, p_address_id uuid, p_payment_method text, p_idempotency_key text, p_coupon_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text, p_invoice_data jsonb DEFAULT NULL::jsonb, p_order_group_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(session_id uuid, idempotency_key text, payment_method text, currency character, status text, expires_at timestamp with time zone, server_subtotal numeric, server_delivery_fee numeric, server_discount numeric, server_coupon_discount numeric, server_commission_amount numeric, server_total numeric, items jsonb, delivery_address jsonb, coupon jsonb, shop jsonb, notes text, warnings jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id UUID;
  v_existing_session RECORD;
  v_item JSONB;
  v_product RECORD;
  v_shop RECORD;
  v_flash_sale RECORD;
  -- `SELECT a.* INTO v_address` yapildigi icin %ROWTYPE birebir uyar; RECORD
  -- yerine bunu kullanmak, adres verilmediginde alanlarin NULL olarak var
  -- olmasini saglar (atanmamis RECORD hatasi olusmaz).
  v_address public.addresses%ROWTYPE;
  v_coupon RECORD;
  v_reservation_id UUID;

  v_item_product_id UUID;
  v_item_quantity INTEGER;
  v_item_variant JSONB;
  v_item_unit_price NUMERIC(12,2);
  v_item_subtotal NUMERIC(12,2);
  v_item_shop_id UUID;
  v_item_product_name TEXT;
  v_item_shop_name TEXT;
  v_item_image_url TEXT;
  v_item_flash_sale_id UUID;
  v_item_flash_price NUMERIC(12,2);

  v_server_subtotal NUMERIC(12,2) := 0;
  v_server_discount NUMERIC(12,2) := 0;
  v_server_coupon_discount NUMERIC(12,2) := 0;
  v_server_delivery_fee NUMERIC(12,2) := 0;
  v_server_commission_amount NUMERIC(12,2) := 0;
  v_server_total NUMERIC(12,2) := 0;

  v_normal_subtotal NUMERIC(12,2) := 0; -- kupon uygulanmamis ara toplam
  v_items_snapshot JSONB := '[]'::JSONB;
  v_warnings JSONB := '[]'::JSONB;

  v_sub_order_subtotals JSONB := '{}'::JSONB;
  v_sub_order_delivery_fees JSONB := '{}'::JSONB;
  -- Urun bazli kargo (products.shipping_fee / free_shipping) icin yardimci degiskenler
  v_prod_max_fee NUMERIC;
  v_prod_all_free BOOLEAN;
  v_sub_order_coupon_discounts JSONB := '{}'::JSONB;

  v_session_id UUID;
  v_now TIMESTAMPTZ := NOW();
  v_expires_at TIMESTAMPTZ;
  v_single_shop_id UUID;
BEGIN
  -- ═════════════════════════════════════════════════════════════════
  -- 1) AUTH + PARAMETRE DOGRULAMA
  -- ═════════════════════════════════════════════════════════════════
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication gerekli (auth.uid() null)' USING ERRCODE = '42501';
  END IF;

  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 OR length(p_idempotency_key) > 128 THEN
    RAISE EXCEPTION 'idempotency_key gerekli (8-128 karakter)' USING ERRCODE = '22023';
  END IF;

  IF p_payment_method NOT IN ('cash','card_on_delivery','balance','online') THEN
    RAISE EXCEPTION 'Gecersiz payment_method: %', p_payment_method USING ERRCODE = '22023';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'items bos olamaz' USING ERRCODE = '22023';
  END IF;

  IF jsonb_array_length(p_items) > 100 THEN
    RAISE EXCEPTION 'Cok fazla item (max 100)' USING ERRCODE = '22023';
  END IF;

  IF p_notes IS NOT NULL AND length(p_notes) > 500 THEN
    RAISE EXCEPTION 'Notes 500 karakteri gecemez' USING ERRCODE = '22023';
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 2) IDEMPOTENCY: ayni user + key ile zaten session var mi?
  -- ═════════════════════════════════════════════════════════════════
  SELECT * INTO v_existing_session
  FROM private.server_checkout_sessions scs
  WHERE scs.user_id = v_user_id
    AND scs.idempotency_key = p_idempotency_key
  LIMIT 1;

  IF FOUND THEN
    -- Mevcut session'i aynen don (idempotent replay)
    -- NOT: expires_at gecmisse status='expired' yapiyoruz, yeniden olusturulmuyor
    IF v_existing_session.expires_at < v_now AND v_existing_session.status = 'pending' THEN
      UPDATE private.server_checkout_sessions
      SET status = 'expired', updated_at = v_now
      WHERE id = v_existing_session.id;
      v_existing_session.status := 'expired';
    END IF;

    -- Mevcut items'i JSON olarak geri ver
    RETURN QUERY
    SELECT
      v_existing_session.id,
      v_existing_session.idempotency_key,
      v_existing_session.payment_method,
      v_existing_session.currency,
      v_existing_session.status,
      v_existing_session.expires_at,
      v_existing_session.server_subtotal,
      v_existing_session.server_delivery_fee,
      v_existing_session.server_discount,
      v_existing_session.server_coupon_discount,
      v_existing_session.server_commission_amount,
      v_existing_session.server_total,
      v_existing_session.items_snapshot,
      v_existing_session.delivery_address_snapshot,
      NULL::JSONB,  -- coupon (reload)
      NULL::JSONB,  -- shop (reload)
      v_existing_session.notes,
      '[]'::JSONB;
    RETURN;
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 3) ADDRESS DOGRULAMA (gercekten bu kullanicinin mi?)
  -- ═════════════════════════════════════════════════════════════════
  IF p_address_id IS NOT NULL THEN
    SELECT a.* INTO v_address
    FROM public.addresses a
    WHERE a.id = p_address_id
      AND a.user_id = v_user_id
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Adres bulunamadi veya bu kullaniciya ait degil' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 4) HER ITEM ICIN: URUN/FIYAT/STOK/VARIANT/FLAS DOGRULAMASI
  -- ═════════════════════════════════════════════════════════════════
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_item_product_id := NULLIF(v_item->>'product_id','')::UUID;
    v_item_quantity := COALESCE((v_item->>'quantity')::INTEGER, 0);
    v_item_variant := v_item->'variant_data';

    IF v_item_product_id IS NULL THEN
      RAISE EXCEPTION 'Gecersiz product_id: %', v_item->>'product_id' USING ERRCODE = '22023';
    END IF;

    IF v_item_quantity <= 0 OR v_item_quantity > 100 THEN
      RAISE EXCEPTION 'Gecersiz quantity (1-100): %', v_item_quantity USING ERRCODE = '22023';
    END IF;

    -- Urun bilgisi (server snapshot)
    SELECT p.id, p.name, p.price, p.discount_price, p.stock_quantity, p.is_available,
           p.shop_id, p.image_url, p.product_type,
           p.min_order_quantity, p.max_order_quantity,
           s.name AS shop_name, s.delivery_fee,
           s.free_delivery_min_amount, s.commission_rate, s.is_active AS shop_is_active,
           NULL::TIMESTAMPTZ AS shop_deleted_at
      INTO v_product
    FROM public.products p
    JOIN public.shops s ON s.id = p.shop_id
    WHERE p.id = v_item_product_id
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Urun bulunamadi: %', v_item_product_id USING ERRCODE = 'P0002';
    END IF;

    IF NOT v_product.is_available THEN
      RAISE EXCEPTION 'Urun satisa kapali: %', v_item_product_id USING ERRCODE = 'P0001';
    END IF;

    IF v_product.shop_is_active = false OR v_product.shop_deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'Magaza aktif degil: %', v_product.shop_id USING ERRCODE = 'P0001';
    END IF;

    IF v_product.stock_quantity < v_item_quantity THEN
      RAISE EXCEPTION 'Yetersiz stok: % (kalan: %, istenen: %)',
        v_item_product_id, v_product.stock_quantity, v_item_quantity
        USING ERRCODE = 'P0001';
    END IF;

    -- Satici tarafindan belirlenen min/max siparis adedi (fiziksel urunler).
    -- Dijital urunlerde miktar araligi min_quantity/max_quantity ile ayrica
    -- yonetildigi icin bu kural uygulanmaz.
    IF COALESCE(v_product.product_type, 'normal') <> 'digital' THEN
      IF v_product.min_order_quantity IS NOT NULL
         AND v_item_quantity < v_product.min_order_quantity THEN
        RAISE EXCEPTION 'Bu urun icin en az % adet siparis verilebilir: %',
          v_product.min_order_quantity, v_product.name
          USING ERRCODE = 'P0001';
      END IF;

      IF v_product.max_order_quantity IS NOT NULL
         AND v_item_quantity > v_product.max_order_quantity THEN
        RAISE EXCEPTION 'Bu urun icin en fazla % adet siparis verilebilir: %',
          v_product.max_order_quantity, v_product.name
          USING ERRCODE = 'P0001';
      END IF;
    END IF;

    -- Variant dogrulamasi (opsiyonel; product_variants tablosu varsa)
    IF v_item_variant IS NOT NULL AND v_item_variant <> 'null'::JSONB THEN
      IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'product_variants'
      ) THEN
        IF NOT EXISTS (
          SELECT 1 FROM public.product_variants pv
          WHERE pv.product_id = v_item_product_id
            AND pv.variant_data = v_item_variant
            AND (pv.stock_quantity IS NULL OR pv.stock_quantity >= v_item_quantity)
        ) THEN
          RAISE EXCEPTION 'Gecersiz variant veya yetersiz variant stoku' USING ERRCODE = 'P0001';
        END IF;
      END IF;
    END IF;

    -- ═════════════════════════════════════════════════════════════════
    -- 4a) FIRSAT: AKTIF FLAS SATIS VAR MI? (server dogrulamali)
    -- ═════════════════════════════════════════════════════════════════
    v_item_flash_sale_id := NULL;
    v_item_flash_price := NULL;
    v_item_unit_price := COALESCE(v_product.discount_price, v_product.price);

    SELECT fs.id, fs.flash_price, fs.original_price, fs.stock_limit, fs.sold_count,
           fs.start_at, fs.end_at, fs.is_active
      INTO v_flash_sale
    FROM public.flash_sales fs
    WHERE fs.product_id = v_item_product_id
      AND fs.shop_id = v_product.shop_id
      AND fs.is_active = true
      AND v_now BETWEEN fs.start_at AND fs.end_at
    ORDER BY fs.flash_price ASC  -- en ucuz flash'i sec
    LIMIT 1
    FOR UPDATE OF fs;  -- ayni anda baska session bu satiri kilitlemesin

    IF FOUND THEN
      -- Stok kontrolu (reservation dahil)
      DECLARE
        v_reserved_qty INTEGER;
        v_available INTEGER;
      BEGIN
        SELECT COALESCE(SUM(fsr.quantity), 0) INTO v_reserved_qty
        FROM private.flash_sale_reservations fsr
        WHERE fsr.sale_id = v_flash_sale.id
          AND fsr.status = 'active'
          AND fsr.expires_at > v_now;

        v_available := v_flash_sale.stock_limit - v_flash_sale.sold_count - v_reserved_qty;

        IF v_available < v_item_quantity THEN
          RAISE EXCEPTION 'Flas satis stoku yetersiz: % (kalan: %, istenen: %)',
            v_item_product_id, v_available, v_item_quantity
            USING ERRCODE = 'P0001';
        END IF;

        v_item_flash_sale_id := v_flash_sale.id;
        v_item_flash_price := v_flash_sale.flash_price;
        v_item_unit_price := v_flash_sale.flash_price;
      END;
    END IF;

    v_item_subtotal := v_item_unit_price * v_item_quantity;
    v_item_shop_id := v_product.shop_id;
    v_item_product_name := v_product.name;
    v_item_shop_name := v_product.shop_name;
    v_item_image_url := v_product.image_url;

    v_server_subtotal := v_server_subtotal + v_item_subtotal;
    v_normal_subtotal := v_normal_subtotal + v_item_subtotal;

    -- Snapshot JSON'a ekle
    v_items_snapshot := v_items_snapshot || jsonb_build_array(jsonb_build_object(
      'product_id', v_item_product_id,
      'product_name', v_item_product_name,
      'shop_id', v_item_shop_id,
      'shop_name', v_item_shop_name,
      'image_url', v_item_image_url,
      'quantity', v_item_quantity,
      'variant_data', v_item_variant,
      'unit_price', v_item_unit_price,
      'subtotal', v_item_subtotal,
      'flash_sale_id', v_item_flash_sale_id,
      'flash_price', v_item_flash_price
    ));

    -- Per-shop alt toplamlar (multi-shop)
    IF v_sub_order_subtotals ? v_item_shop_id::TEXT THEN
      v_sub_order_subtotals := jsonb_set(
        v_sub_order_subtotals,
        ARRAY[v_item_shop_id::TEXT],
        to_jsonb((v_sub_order_subtotals->>v_item_shop_id::TEXT)::NUMERIC + v_item_subtotal)
      );
    ELSE
      v_sub_order_subtotals := v_sub_order_subtotals ||
        jsonb_build_object(v_item_shop_id::TEXT, v_item_subtotal);
    END IF;
  END LOOP;

  -- ═════════════════════════════════════════════════════════════════
  -- 5) TEK-MAGAZA MI COK-MAGAZA MI TESPIT ET
  -- ═════════════════════════════════════════════════════════════════
  DECLARE
    v_shop_count INTEGER;
  BEGIN
    -- NOT: burada LATERAL alt sorgu kolonu `v_item_shop_id` olarak
    -- adlandirilmisti; ayni isimde bir PL/pgSQL degiskeni oldugu icin
    -- "42702 ambiguous" hatasi veriyordu. Ifade dogrudan yazilarak
    -- ayni sonuc ambiguity olmadan elde ediliyor.
    SELECT COUNT(DISTINCT (e->>'shop_id')::UUID) INTO v_shop_count
    FROM jsonb_array_elements(v_items_snapshot) AS e;

    IF v_shop_count > 1 THEN
      -- Cok magazali: her magaza icin ayri delivery_fee hesaplanir
      DECLARE
        v_shop_key TEXT;
        v_shop_subtotal NUMERIC;
        v_shop_delivery_fee NUMERIC;
        v_shop_min_free NUMERIC;
        v_shop_base_fee NUMERIC;
      BEGIN
        FOR v_shop_key, v_shop_subtotal IN
          SELECT key, (value::TEXT)::NUMERIC
          FROM jsonb_each(v_sub_order_subtotals)
        LOOP
          SELECT s.delivery_fee, s.free_delivery_min_amount
            INTO v_shop_base_fee, v_shop_min_free
          FROM public.shops s WHERE s.id = v_shop_key::UUID;

          -- Urun bazli kargo: bu magazanin sepetteki urunlerinden
          --   * hepsi free_shipping ise kargo 0,
          --   * degilse shipping_fee tanimli urunlerin en yuksegi magaza ucretinin yerine gecer.
          SELECT MAX(pp.shipping_fee), BOOL_AND(COALESCE(pp.free_shipping, false))
            INTO v_prod_max_fee, v_prod_all_free
          FROM jsonb_array_elements(v_items_snapshot) AS e
          JOIN public.products pp ON pp.id = (e->>'product_id')::UUID
          WHERE (e->>'shop_id')::UUID = v_shop_key::UUID;

          IF COALESCE(v_prod_all_free, false) THEN
            v_shop_delivery_fee := 0;
          ELSIF v_shop_min_free > 0 AND v_shop_subtotal >= v_shop_min_free THEN
            v_shop_delivery_fee := 0;
          ELSIF v_prod_max_fee IS NOT NULL THEN
            v_shop_delivery_fee := v_prod_max_fee;
          ELSE
            v_shop_delivery_fee := COALESCE(v_shop_base_fee, 15.0);
          END IF;

          v_server_delivery_fee := v_server_delivery_fee + v_shop_delivery_fee;
          v_sub_order_delivery_fees := v_sub_order_delivery_fees ||
            jsonb_build_object(v_shop_key, v_shop_delivery_fee);
        END LOOP;
      END;
    ELSE
      -- Tek magaza: v_shop_id'yi set et
      SELECT (v_items_snapshot->0->>'shop_id')::UUID INTO v_single_shop_id;

      -- Delivery fee (tek magaza)
      SELECT s.delivery_fee, s.free_delivery_min_amount, s.commission_rate
        INTO v_shop
      FROM public.shops s WHERE s.id = v_single_shop_id;

      SELECT MAX(pp.shipping_fee), BOOL_AND(COALESCE(pp.free_shipping, false))
        INTO v_prod_max_fee, v_prod_all_free
      FROM jsonb_array_elements(v_items_snapshot) AS e
      JOIN public.products pp ON pp.id = (e->>'product_id')::UUID;

      IF COALESCE(v_prod_all_free, false) THEN
        v_server_delivery_fee := 0;
      ELSIF v_shop.free_delivery_min_amount > 0 AND v_normal_subtotal >= v_shop.free_delivery_min_amount THEN
        v_server_delivery_fee := 0;
      ELSIF v_prod_max_fee IS NOT NULL THEN
        v_server_delivery_fee := v_prod_max_fee;
      ELSE
        v_server_delivery_fee := COALESCE(v_shop.delivery_fee, 15.0);
      END IF;
    END IF;
  END;

  -- ═════════════════════════════════════════════════════════════════
  -- 6) KUPON DOGRULAMA + INDIRIM HESAPLAMA (server)
  -- ═════════════════════════════════════════════════════════════════
  -- v_coupon bir RECORD; kupon verilmediginde hic atanmazsa asagidaki
  -- RETURN QUERY icinde "55000 record is not assigned yet" hatasi olusur
  -- (PL/pgSQL, secilmeyen CASE dali icin bile RECORD'un yapisini bilmek
  -- zorunda). Bu yuzden once ayni kolon adlari/tipleriyle bos bir satir
  -- atanip yapi sabitleniyor; kupon varsa hemen ustune yaziliyor.
  SELECT NULL::UUID    AS id,      NULL::TEXT    AS code,
         NULL::TEXT    AS discount_type,         NULL::NUMERIC AS discount_value,
         NULL::NUMERIC AS maximum_discount_amount,
         NULL::NUMERIC AS minimum_order_amount,
         NULL::INTEGER AS usage_limit,           NULL::INTEGER AS usage_count,
         NULL::INTEGER AS usage_per_user,
         NULL::TIMESTAMPTZ AS start_date,        NULL::TIMESTAMPTZ AS end_date,
         NULL::BOOLEAN AS is_active,             NULL::UUID    AS shop_id
    INTO v_coupon;

  IF p_coupon_id IS NOT NULL THEN
    SELECT c.id, c.code, c.discount_type, c.discount_value, c.maximum_discount_amount,
           c.minimum_order_amount, c.usage_limit, c.usage_count, c.usage_per_user,
           c.start_date, c.end_date, c.is_active, c.shop_id
      INTO v_coupon
    FROM public.shop_coupons c
    WHERE c.id = p_coupon_id
    LIMIT 1
    FOR UPDATE OF c;  -- ayni anda iki session ayni kupona erisemesin

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Kupon bulunamadi' USING ERRCODE = 'P0002';
    END IF;

    IF NOT v_coupon.is_active THEN
      RAISE EXCEPTION 'Kupon aktif degil' USING ERRCODE = 'P0001';
    END IF;

    IF v_coupon.start_date IS NOT NULL AND v_coupon.start_date > v_now THEN
      RAISE EXCEPTION 'Kupon henuz baslamadi' USING ERRCODE = 'P0001';
    END IF;

    IF v_coupon.end_date IS NOT NULL AND v_coupon.end_date < v_now THEN
      RAISE EXCEPTION 'Kuponun suresi dolmus' USING ERRCODE = 'P0001';
    END IF;

    -- Kupon magaza uyumu (cok magazali ise en az bir item uyumlu olmali)
    IF v_single_shop_id IS NOT NULL AND v_coupon.shop_id <> v_single_shop_id THEN
      RAISE EXCEPTION 'Kupon bu magaza icin gecerli degil' USING ERRCODE = 'P0001';
    END IF;

    IF v_coupon.minimum_order_amount IS NOT NULL
       AND v_normal_subtotal < v_coupon.minimum_order_amount THEN
      RAISE EXCEPTION 'Minimum siparis tutari asilmadi (gerekli: %, mevcut: %)',
        v_coupon.minimum_order_amount, v_normal_subtotal
        USING ERRCODE = 'P0001';
    END IF;

    -- Kullanici basina limit
    IF v_coupon.usage_per_user IS NOT NULL THEN
      DECLARE
        v_user_usage_count INTEGER;
      BEGIN
        SELECT COUNT(*) INTO v_user_usage_count
        FROM public.coupon_usages
        WHERE coupon_id = v_coupon.id AND user_id = v_user_id;
        IF v_user_usage_count >= v_coupon.usage_per_user THEN
          RAISE EXCEPTION 'Bu kuponu daha once kullandiniz' USING ERRCODE = 'P0001';
        END IF;
      END;
    END IF;

    -- Kupon indirimi hesapla
    IF v_coupon.discount_type = 'percentage' THEN
      v_server_coupon_discount := v_normal_subtotal * (v_coupon.discount_value / 100.0);
    ELSIF v_coupon.discount_type = 'fixed' THEN
      v_server_coupon_discount := v_coupon.discount_value;
    ELSE
      RAISE EXCEPTION 'Bilinmeyen kupon tipi: %', v_coupon.discount_type USING ERRCODE = 'P0001';
    END IF;

    -- Maksimum indirim siniri
    IF v_coupon.maximum_discount_amount IS NOT NULL
       AND v_server_coupon_discount > v_coupon.maximum_discount_amount THEN
      v_server_coupon_discount := v_coupon.maximum_discount_amount;
    END IF;

    -- Negatif olamaz, subtotal'i asamaz
    IF v_server_coupon_discount < 0 THEN
      v_server_coupon_discount := 0;
    END IF;
    IF v_server_coupon_discount > v_normal_subtotal THEN
      v_server_coupon_discount := v_normal_subtotal;
    END IF;
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 7) KOMISYON (server, shops.commission_rate)
  -- ═════════════════════════════════════════════════════════════════
  v_server_commission_amount := ROUND(v_normal_subtotal * (v_shop.commission_rate / 100.0), 2);

  -- ═════════════════════════════════════════════════════════════════
  -- 8) TOPLAM HESAPLA + DOGRULAMALAR
  -- ═════════════════════════════════════════════════════════════════
  v_server_total := v_server_subtotal + v_server_delivery_fee - v_server_coupon_discount - v_server_discount;

  IF v_server_total < 0 THEN
    v_server_total := 0;
  END IF;

  -- Ucretli urunlerde total=0 kabul edilmez
  -- (free-order policy: ayri bir mekanizma; su an sadece 'total>0' zorunludur)
  IF v_server_total <= 0 AND v_normal_subtotal > 0 THEN
    -- Bu durumda ya kuponsuz olur ya da limit; simdilik izin ver (kupon %100 ise)
    -- Eger magazada free-order politikasi yoksa hata ver
    NULL; -- policy hook (ileride)
  END IF;

  v_expires_at := v_now + INTERVAL '15 minutes';

  -- ═════════════════════════════════════════════════════════════════
  -- 9) FLAS REZERVASYONLARINI OLUSTUR (FOR UPDATE kilitleriyle)
  -- ═════════════════════════════════════════════════════════════════
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_snapshot)
  LOOP
    IF (v_item->>'flash_sale_id') IS NOT NULL THEN
      INSERT INTO private.flash_sale_reservations (
        sale_id, session_id, user_id, product_id, shop_id,
        quantity, unit_price, original_price, expires_at
      ) VALUES (
        (v_item->>'flash_sale_id')::UUID,
        gen_random_uuid(),  -- placeholder, INSERT sonrasi update edilecek
        v_user_id,
        (v_item->>'product_id')::UUID,
        (v_item->>'shop_id')::UUID,
        (v_item->>'quantity')::INTEGER,
        (v_item->>'unit_price')::NUMERIC,
        COALESCE(
          (SELECT original_price FROM public.flash_sales WHERE id = (v_item->>'flash_sale_id')::UUID),
          (v_item->>'unit_price')::NUMERIC
        ),
        v_expires_at
      );
    END IF;
  END LOOP;

  -- ═════════════════════════════════════════════════════════════════
  -- 10) SESSION INSERT
  -- ═════════════════════════════════════════════════════════════════
  INSERT INTO private.server_checkout_sessions (
    user_id, idempotency_key, payment_method, currency,
    address_id, coupon_id, order_group_id,
    server_subtotal, server_delivery_fee, server_discount, server_coupon_discount,
    server_commission_amount, server_total,
    sub_order_subtotals, sub_order_delivery_fees, sub_order_coupon_discounts,
    items_snapshot, delivery_address_snapshot,
    expires_at, notes, invoice_data
  ) VALUES (
    v_user_id, p_idempotency_key, p_payment_method, 'TRY',
    p_address_id, p_coupon_id, p_order_group_id,
    v_server_subtotal, v_server_delivery_fee, v_server_discount, v_server_coupon_discount,
    v_server_commission_amount, v_server_total,
    v_sub_order_subtotals, v_sub_order_delivery_fees, v_sub_order_coupon_discounts,
    v_items_snapshot,
    CASE WHEN v_address.id IS NOT NULL THEN jsonb_build_object(
      'id', v_address.id,
      'title', v_address.title,
      'full_name', v_address.full_name,
      'phone', v_address.phone,
      'address_line1', v_address.address_line1,
      'address_line2', v_address.address_line2,
      'city', v_address.city,
      'district', v_address.district,
      'postal_code', v_address.postal_code,
      'latitude', v_address.latitude,
      'longitude', v_address.longitude
    ) ELSE NULL END,
    v_expires_at, p_notes, p_invoice_data
  )
  RETURNING id INTO v_session_id;

  -- Rezervasyonlara session_id'yi set et
  UPDATE private.flash_sale_reservations fsr
  SET session_id = v_session_id
  WHERE fsr.user_id = v_user_id
    AND fsr.session_id = gen_random_uuid()  -- placeholder (yukardaki INSERT ile ayni)
    AND fsr.status = 'active'
    AND fsr.created_at >= v_now - INTERVAL '1 second';

  -- Audit log
  INSERT INTO private.server_checkout_audit (session_id, user_id, event_type, detail)
  VALUES (v_session_id, v_user_id, 'session_prepared', jsonb_build_object(
    'payment_method', p_payment_method,
    'item_count', jsonb_array_length(v_items_snapshot),
    'subtotal', v_server_subtotal,
    'total', v_server_total
  ));

  -- ═════════════════════════════════════════════════════════════════
  -- 11) QUOTE DON
  -- ═════════════════════════════════════════════════════════════════
  RETURN QUERY
  SELECT
    v_session_id,
    p_idempotency_key,
    p_payment_method,
    'TRY'::CHAR(3),
    'pending'::TEXT,
    v_expires_at,
    v_server_subtotal,
    v_server_delivery_fee,
    v_server_discount,
    v_server_coupon_discount,
    v_server_commission_amount,
    v_server_total,
    v_items_snapshot,
    CASE WHEN v_address.id IS NOT NULL THEN jsonb_build_object(
      'id', v_address.id,
      'full_name', v_address.full_name,
      'phone', v_address.phone,
      'address_line1', v_address.address_line1,
      'city', v_address.city
    ) ELSE NULL END,
    CASE WHEN v_coupon.id IS NOT NULL THEN jsonb_build_object(
      'id', v_coupon.id,
      'code', v_coupon.code,
      'discount_type', v_coupon.discount_type,
      'discount_value', v_coupon.discount_value
    ) ELSE NULL END,
    CASE WHEN v_single_shop_id IS NOT NULL THEN jsonb_build_object(
      'id', v_single_shop_id,
      'delivery_fee', v_shop.delivery_fee,
      'commission_rate', v_shop.commission_rate,
      'free_delivery_min_amount', v_shop.free_delivery_min_amount
    ) ELSE NULL END,
    p_notes,
    v_warnings;
END;
$function$
;

COMMIT;

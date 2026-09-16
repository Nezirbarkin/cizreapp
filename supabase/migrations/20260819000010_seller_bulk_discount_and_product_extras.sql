-- ============================================================================
-- 2026-08-19 | Satici paneli: coklu (toplu) indirim + urun ek ozellikleri
-- ============================================================================
-- Bu migration UC sey yapar:
--
--  1) products tablosuna satici tarafindan yonetilen ek alanlar ekler:
--       - badges                (urun rozetleri, en fazla 3 adet, sabit liste)
--       - prep_time_min_days /  (hazirlik / kargoya verilis suresi, gun)
--         prep_time_max_days
--       - shipping_fee          (urune ozel kargo ucreti; magaza ucretini ezer)
--       - free_shipping         (urune ozel ucretsiz kargo)
--       - min_order_quantity /  (fiziksel urunlerde siparis adedi siniri)
--         max_order_quantity
--     Hepsi NULL / false varsayilanli -> mevcut urunlerin davranisi DEGISMEZ.
--
--  2) Toplu indirim RPC'lerini ekler (seller_bulk_set_discount /
--     seller_bulk_set_badges). Sunucu-otoriteli: caller'in gercekten o
--     urunlerin magaza sahibi oldugu dogrulanir ve indirimli fiyat sunucuda
--     hesaplanir; istemciden fiyat kabul edilmez.
--
--  3) private.prepare_checkout_session'i yeni alanlari dikkate alacak sekilde
--     gunceller. Fonksiyonun geri kalani CANLI SURUMDEN BIREBIR kopyalanmistir;
--     yalnizca su noktalara ekleme yapilmistir:
--       - urun snapshot SELECT'ine yeni kolonlar,
--       - min / max siparis adedi dogrulamasi,
--       - kargo ucreti hesabinda urun bazli kargo onceligi.
--     Yeni alanlar bos oldugunda hesaplama eskisiyle AYNI sonucu verir.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1) YENI KOLONLAR
-- ----------------------------------------------------------------------------

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS badges             TEXT[]        NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS prep_time_min_days INTEGER,
  ADD COLUMN IF NOT EXISTS prep_time_max_days INTEGER,
  ADD COLUMN IF NOT EXISTS shipping_fee       NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS free_shipping      BOOLEAN       NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS min_order_quantity INTEGER,
  ADD COLUMN IF NOT EXISTS max_order_quantity INTEGER;

COMMENT ON COLUMN public.products.badges IS
  'Satici rozetleri. Izinli deger listesi products_badges_allowed constraintinde.';
COMMENT ON COLUMN public.products.shipping_fee IS
  'Urune ozel kargo ucreti. NULL = magazanin shops.delivery_fee degeri kullanilir. Sepette ayni magazadan birden fazla urun varsa en yuksek shipping_fee gecerlidir.';
COMMENT ON COLUMN public.products.free_shipping IS
  'true ise bu urun kargo ucretsizdir. Bir magazanin sepetteki TUM urunleri free_shipping ise o magazanin kargo ucreti 0 olur.';

-- Rozet whitelist'i + adet siniri
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_badges_allowed;
ALTER TABLE public.products ADD CONSTRAINT products_badges_allowed CHECK (
  badges <@ ARRAY[
    'yeni', 'cok_satan', 'sinirli_stok', 'el_yapimi', 'organik',
    'yerli_uretim', 'ithal', 'garantili', 'son_firsat'
  ]::TEXT[]
  AND COALESCE(array_length(badges, 1), 0) <= 3
);

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_prep_time_valid;
ALTER TABLE public.products ADD CONSTRAINT products_prep_time_valid CHECK (
  (prep_time_min_days IS NULL OR (prep_time_min_days >= 0 AND prep_time_min_days <= 365))
  AND (prep_time_max_days IS NULL OR (prep_time_max_days >= 0 AND prep_time_max_days <= 365))
  AND (
    prep_time_min_days IS NULL OR prep_time_max_days IS NULL
    OR prep_time_max_days >= prep_time_min_days
  )
);

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_shipping_fee_valid;
ALTER TABLE public.products ADD CONSTRAINT products_shipping_fee_valid CHECK (
  shipping_fee IS NULL OR shipping_fee >= 0
);

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_order_quantity_valid;
ALTER TABLE public.products ADD CONSTRAINT products_order_quantity_valid CHECK (
  (min_order_quantity IS NULL OR min_order_quantity >= 1)
  AND (max_order_quantity IS NULL OR max_order_quantity >= 1)
  AND (
    min_order_quantity IS NULL OR max_order_quantity IS NULL
    OR max_order_quantity >= min_order_quantity
  )
);

-- Satici panelindeki "indirimli urunler" filtresi icin
CREATE INDEX IF NOT EXISTS idx_products_shop_discount
  ON public.products (shop_id)
  WHERE discount_price IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 2) TOPLU INDIRIM RPC'LERI
-- ----------------------------------------------------------------------------

-- Secilen urunlere tek islemde indirim uygular / kaldirir.
--
-- p_mode:
--   'percent'     -> discount_price = price * (1 - p_value / 100)
--   'amount'      -> discount_price = price - p_value
--   'fixed_price' -> discount_price = p_value
--   'clear'       -> discount_price = NULL (indirimi kaldir)
--
-- Yalnizca caller'in sahibi oldugu magazalarin urunleri guncellenir. Sonucu
-- gecersiz olan (0 veya alti, ya da fiyattan dusuk olmayan) urunler sessizce
-- atlanir; dijital urunlere indirim uygulanmaz. Donus: guncellenen urun sayisi.
CREATE OR REPLACE FUNCTION public.seller_bulk_set_discount(
  p_product_ids UUID[],
  p_mode        TEXT,
  p_value       NUMERIC DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_user_id UUID := auth.uid();
  v_updated INTEGER := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'seller_bulk_set_discount: oturum bulunamadi'
      USING ERRCODE = '28000';
  END IF;

  IF p_product_ids IS NULL OR array_length(p_product_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'En az bir urun secmelisiniz' USING ERRCODE = '22023';
  END IF;

  IF array_length(p_product_ids, 1) > 500 THEN
    RAISE EXCEPTION 'Tek seferde en fazla 500 urun guncellenebilir'
      USING ERRCODE = '22023';
  END IF;

  IF p_mode NOT IN ('percent', 'amount', 'fixed_price', 'clear') THEN
    RAISE EXCEPTION 'Gecersiz indirim tipi: %', p_mode USING ERRCODE = '22023';
  END IF;

  IF p_mode = 'clear' THEN
    UPDATE public.products p
       SET discount_price = NULL,
           updated_at     = NOW()
     WHERE p.id = ANY(p_product_ids)
       AND p.discount_price IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.shops s
          WHERE s.id = p.shop_id AND s.owner_id = v_user_id
       );

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN v_updated;
  END IF;

  IF p_value IS NULL THEN
    RAISE EXCEPTION 'Indirim degeri bos olamaz' USING ERRCODE = '22023';
  END IF;

  IF p_mode = 'percent' AND (p_value <= 0 OR p_value > 95) THEN
    RAISE EXCEPTION 'Yuzde indirim 1 ile 95 arasinda olmalidir'
      USING ERRCODE = '22023';
  END IF;

  IF p_mode IN ('amount', 'fixed_price') AND p_value <= 0 THEN
    RAISE EXCEPTION 'Indirim degeri sifirdan buyuk olmalidir'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.products p
     SET discount_price = calc.new_price,
         updated_at     = NOW()
    FROM (
      SELECT pp.id,
             ROUND(
               CASE p_mode
                 WHEN 'percent'     THEN pp.price * (1 - p_value / 100.0)
                 WHEN 'amount'      THEN pp.price - p_value
                 WHEN 'fixed_price' THEN p_value
               END, 2) AS new_price
        FROM public.products pp
        JOIN public.shops s ON s.id = pp.shop_id
       WHERE pp.id = ANY(p_product_ids)
         AND s.owner_id = v_user_id
         AND COALESCE(pp.product_type, 'normal') <> 'digital'
    ) AS calc
   WHERE p.id = calc.id
     -- Gecersiz sonuclari sessizce atla: fiyati sifirlayan ya da fiyatin
     -- altina inmeyen bir "indirim" musteriye yanlis fiyat gosterirdi.
     AND calc.new_price > 0
     AND calc.new_price < p.price
     AND p.discount_price IS DISTINCT FROM calc.new_price;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$fn$;

REVOKE ALL ON FUNCTION public.seller_bulk_set_discount(UUID[], TEXT, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seller_bulk_set_discount(UUID[], TEXT, NUMERIC) TO authenticated;

-- Secilen urunlerin rozetlerini tek islemde ayarlar (mevcut rozetlerin yerine gecer).
CREATE OR REPLACE FUNCTION public.seller_bulk_set_badges(
  p_product_ids UUID[],
  p_badges      TEXT[]
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_user_id UUID := auth.uid();
  v_badges  TEXT[];
  v_updated INTEGER := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'seller_bulk_set_badges: oturum bulunamadi'
      USING ERRCODE = '28000';
  END IF;

  IF p_product_ids IS NULL OR array_length(p_product_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'En az bir urun secmelisiniz' USING ERRCODE = '22023';
  END IF;

  IF array_length(p_product_ids, 1) > 500 THEN
    RAISE EXCEPTION 'Tek seferde en fazla 500 urun guncellenebilir'
      USING ERRCODE = '22023';
  END IF;

  -- Tekrarlari temizle; gecersiz rozetleri CHECK constraint zaten reddeder.
  SELECT COALESCE(array_agg(DISTINCT b), '{}'::TEXT[])
    INTO v_badges
  FROM unnest(COALESCE(p_badges, '{}'::TEXT[])) AS b
  WHERE b IS NOT NULL AND b <> '';

  IF COALESCE(array_length(v_badges, 1), 0) > 3 THEN
    RAISE EXCEPTION 'Bir urune en fazla 3 rozet eklenebilir' USING ERRCODE = '22023';
  END IF;

  UPDATE public.products p
     SET badges     = v_badges,
         updated_at = NOW()
   WHERE p.id = ANY(p_product_ids)
     AND p.badges IS DISTINCT FROM v_badges
     AND EXISTS (
       SELECT 1 FROM public.shops s
        WHERE s.id = p.shop_id AND s.owner_id = v_user_id
     );

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$fn$;

REVOKE ALL ON FUNCTION public.seller_bulk_set_badges(UUID[], TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seller_bulk_set_badges(UUID[], TEXT[]) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3) add_product: yeni alanlari da yazabilsin.
--    Yeni parametrelerin hepsi DEFAULT'lu, ancak PostgreSQL fonksiyonlari
--    argüman tipi listesine gore tanidigi icin parametre eklemek REPLACE degil
--    yeni bir OVERLOAD yaratir. Iki overload birlikte dururken adlandirilmis
--    parametrelerle yapilan cagri "function is not unique" hatasi verir; bu
--    yuzden eski 14 parametreli surum once dusurulur.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.add_product(
  uuid, text, text, numeric, numeric, integer, text, text, text,
  jsonb, text, jsonb, jsonb, jsonb
);

CREATE OR REPLACE FUNCTION public.add_product(
  p_shop_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_price NUMERIC,
  p_old_price NUMERIC,
  p_stock INTEGER,
  p_image_url TEXT,
  p_category TEXT,
  p_slug TEXT,
  p_additional_images JSONB DEFAULT '[]'::JSONB,
  p_product_type TEXT DEFAULT 'normal'::TEXT,
  p_sizes JSONB DEFAULT '[]'::JSONB,
  p_shoe_sizes JSONB DEFAULT '[]'::JSONB,
  p_colors JSONB DEFAULT '[]'::JSONB,
  p_badges TEXT[] DEFAULT '{}'::TEXT[],
  p_prep_time_min_days INTEGER DEFAULT NULL,
  p_prep_time_max_days INTEGER DEFAULT NULL,
  p_shipping_fee NUMERIC DEFAULT NULL,
  p_free_shipping BOOLEAN DEFAULT false,
  p_min_order_quantity INTEGER DEFAULT NULL,
  p_max_order_quantity INTEGER DEFAULT NULL,
  p_campaign_type TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_owner_id UUID;
  v_product_id UUID;
BEGIN
  -- Shop'un gercekten bu kullaniciya ait oldugunu dogrula
  SELECT owner_id INTO v_owner_id
  FROM shops
  WHERE id = p_shop_id
  LIMIT 1;

  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Magaza bulunamadi';
  END IF;

  IF v_owner_id != auth.uid() THEN
    RAISE EXCEPTION 'Bu magazaya urun ekleme yetkiniz yok';
  END IF;

  INSERT INTO products (
    shop_id, name, slug, description, price, old_price, stock_quantity,
    image_url, category, is_active, is_available,
    additional_images, product_type, sizes, shoe_sizes, colors,
    badges, prep_time_min_days, prep_time_max_days,
    shipping_fee, free_shipping, min_order_quantity, max_order_quantity,
    campaign_type
  )
  VALUES (
    p_shop_id, p_name, p_slug, p_description, p_price, p_old_price, p_stock,
    p_image_url, p_category, true, true,
    p_additional_images, p_product_type, p_sizes, p_shoe_sizes, p_colors,
    COALESCE(p_badges, '{}'::TEXT[]), p_prep_time_min_days, p_prep_time_max_days,
    p_shipping_fee, COALESCE(p_free_shipping, false),
    p_min_order_quantity, p_max_order_quantity,
    p_campaign_type
  )
  RETURNING id INTO v_product_id;

  RETURN v_product_id;
END;
$fn$;

-- ----------------------------------------------------------------------------
-- 4) CHECKOUT: urun bazli kargo + min / max siparis adedi
--    Asagidaki tanim canli surumun birebir kopyasidir; yapilan eklemeler
--    dosyanin basindaki aciklamada listelenmistir.
-- ----------------------------------------------------------------------------

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
  v_address RECORD;
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
  FROM private.server_checkout_sessions
  WHERE user_id = v_user_id
    AND idempotency_key = p_idempotency_key
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
           s.deleted_at AS shop_deleted_at
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
        SELECT COALESCE(SUM(quantity), 0) INTO v_reserved_qty
        FROM private.flash_sale_reservations
        WHERE sale_id = v_flash_sale.id
          AND status = 'active'
          AND expires_at > v_now;

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
    SELECT COUNT(DISTINCT v_item_shop_id) INTO v_shop_count
    FROM jsonb_array_elements(v_items_snapshot) AS e
    CROSS JOIN LATERAL (SELECT (e->>'shop_id')::UUID AS v_item_shop_id) AS s
    WHERE TRUE;

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
  UPDATE private.flash_sale_reservations
  SET session_id = v_session_id
  WHERE user_id = v_user_id
    AND session_id = gen_random_uuid()  -- placeholder (yukardaki INSERT ile ayni)
    AND status = 'active'
    AND created_at >= v_now - INTERVAL '1 second';

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

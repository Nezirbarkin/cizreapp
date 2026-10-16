-- ============================================================================
-- Satıcı toplu ürün yükleme / güncelleme (2026-10-15)
--
--   public.seller_bulk_upsert_products(p_shop_id, p_items)
--
-- Tek çağrıda en fazla 100 satır. Her satır KENDİ alt işleminde çalışır: hatalı
-- satır geri alınır, diğerleri kaydedilir. Dönüş satır satır sonuçtur:
--   { created, updated, failed, added_categories: [..],
--     results: [ {i, ok, action:'created'|'updated', id} | {i, ok:false, error, code} ] }
--
-- Satır (jsonb nesnesi):
--   id               → varsa GÜNCELLEME (ürün bu mağazanın olmalı, yalnız fiziksel).
--                      Güncellemede yalnız GÖNDERİLEN anahtarlar değişir; null
--                      gönderilen boşaltılabilir alan temizlenir.
--   product_type     → 'normal' (varsayılan) | 'digital'
--   name, description, price, old_price, stock, category, image_url,
--   additional_images[], is_available, shipping_fee, free_shipping,
--   min_order_quantity, max_order_quantity, badges[]
--   Dijital: smm_provider_id, smm_service_id, price_per_1000, min_quantity,
--   max_quantity, max_orders_per_user, provider_rate, service_name
--   (provider_rate/service_name smm_product_baselines'a yazılır; products'a
--   KONMAZ — sağlayıcı fiyatı satıcının maliyetidir, ürün tablosu herkese açık).
--
-- Neden add_product değil: add_product dijital alanları hiç almıyor (dijital
-- ürün chk_digital_fields'a takılıp istemcinin doğrudan INSERT yedeğine
-- düşüyor), slug'ı istemci üretiyor (aynı ad ikinci kez eklenemiyor) ve satır
-- başına bir istek demek. Burada slug sunucuda benzersizleştirilir.
--
-- Mağazada olmayan kategoriler shops.seller_categories'e eklenir (form yalnız
-- mağaza kategorilerini seçtirdiği için ürün başka türlü mağaza sekmelerinde
-- görünmezdi).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.seller_bulk_upsert_products(
  p_shop_id UUID,
  p_items   JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_uid          UUID := auth.uid();
  v_owner        UUID;
  v_shop_cats    JSONB;
  v_cat_keys     TEXT[] := '{}';
  v_new_cats     TEXT[] := '{}';
  v_item         JSONB;
  v_idx          INTEGER := -1;
  v_results      JSONB := '[]'::JSONB;
  v_created      INTEGER := 0;
  v_updated      INTEGER := 0;
  v_failed       INTEGER := 0;

  v_existing     public.products%ROWTYPE;
  v_is_update    BOOLEAN;
  v_type         TEXT;
  v_id           UUID;
  v_name         TEXT;
  v_desc         TEXT;
  v_price        NUMERIC;
  v_old_price    NUMERIC;
  v_stock        INTEGER;
  v_category     TEXT;
  v_image        TEXT;
  v_extra        JSONB;
  v_available    BOOLEAN;
  v_ship_fee     NUMERIC;
  v_free_ship    BOOLEAN;
  v_min_order    INTEGER;
  v_max_order    INTEGER;
  v_badges       TEXT[];
  v_provider_id  UUID;
  v_service_id   TEXT;
  v_per_1000     NUMERIC;
  v_min_qty      INTEGER;
  v_max_qty      INTEGER;
  v_max_per_user INTEGER;
  v_slug         TEXT;
  v_url          TEXT;

  v_state        TEXT;
  v_constraint   TEXT;
  v_message      TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'seller_bulk_upsert_products: oturum bulunamadi'
      USING ERRCODE = '28000';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Yüklenecek ürün yok' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items) > 100 THEN
    RAISE EXCEPTION 'Tek seferde en fazla 100 ürün gönderilebilir'
      USING ERRCODE = '22023';
  END IF;

  -- Mağaza satırı kilitlenir: aynı mağazaya eşzamanlı iki toplu yükleme slug
  -- ve kategori listesinde birbirini ezmesin.
  SELECT s.owner_id, COALESCE(s.seller_categories, '[]'::JSONB)
    INTO v_owner, v_shop_cats
    FROM public.shops s
   WHERE s.id = p_shop_id
   FOR UPDATE;

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Mağaza bulunamadı' USING ERRCODE = 'P0002';
  END IF;
  IF v_owner <> v_uid THEN
    RAISE EXCEPTION 'Bu mağazaya ürün ekleme yetkiniz yok' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(array_agg(lower(btrim(c))), '{}')
    INTO v_cat_keys
    FROM jsonb_array_elements_text(
           CASE WHEN jsonb_typeof(v_shop_cats) = 'array' THEN v_shop_cats ELSE '[]'::JSONB END
         ) AS c;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_idx := v_idx + 1;

    BEGIN
      IF jsonb_typeof(v_item) <> 'object' THEN
        RAISE EXCEPTION 'Satır biçimi geçersiz' USING ERRCODE = 'P0001';
      END IF;

      v_is_update := NULLIF(btrim(COALESCE(v_item->>'id', '')), '') IS NOT NULL;
      v_type := COALESCE(NULLIF(btrim(v_item->>'product_type'), ''), 'normal');

      IF v_type NOT IN ('normal', 'digital') THEN
        RAISE EXCEPTION 'Toplu yüklemede yalnız standart ve dijital ürün desteklenir'
          USING ERRCODE = 'P0001';
      END IF;

      -- ── Ortak alanlar (yalnız gönderildiyse okunur) ─────────────────────────
      IF v_is_update THEN
        SELECT * INTO v_existing
          FROM public.products p
         WHERE p.id = (v_item->>'id')::UUID AND p.shop_id = p_shop_id
         FOR UPDATE;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Ürün bulunamadı (ürün kodu bu mağazaya ait değil)'
            USING ERRCODE = 'P0001';
        END IF;
        IF v_existing.product_type = 'digital' OR v_type = 'digital' THEN
          RAISE EXCEPTION 'Dijital ürünler dosyayla güncellenemez'
            USING ERRCODE = 'P0001';
        END IF;
        IF v_existing.product_type IN ('clothing', 'shoes') AND v_item ? 'stock' THEN
          RAISE EXCEPTION 'Bedenli/numaralı ürünün stoğu renk varyantlarından yönetilir'
            USING ERRCODE = 'P0001';
        END IF;

        v_id        := v_existing.id;
        v_name      := v_existing.name;
        v_desc      := v_existing.description;
        v_price     := v_existing.price;
        v_old_price := v_existing.old_price;
        v_stock     := v_existing.stock_quantity;
        v_category  := v_existing.category;
        v_image     := v_existing.image_url;
        v_extra     := COALESCE(v_existing.additional_images, '[]'::JSONB);
        v_available := COALESCE(v_existing.is_available, true);
        v_ship_fee  := v_existing.shipping_fee;
        v_free_ship := v_existing.free_shipping;
        v_min_order := v_existing.min_order_quantity;
        v_max_order := v_existing.max_order_quantity;
        v_badges    := v_existing.badges;
      ELSE
        v_id        := NULL;
        v_name      := NULL;
        v_desc      := NULL;
        v_price     := NULL;
        v_old_price := NULL;
        v_stock     := NULL;
        v_category  := NULL;
        v_image     := NULL;
        v_extra     := '[]'::JSONB;
        v_available := true;
        v_ship_fee  := NULL;
        v_free_ship := false;
        v_min_order := NULL;
        v_max_order := NULL;
        v_badges    := '{}';
      END IF;

      IF v_item ? 'name' AND NULLIF(btrim(v_item->>'name'), '') IS NOT NULL THEN
        v_name := regexp_replace(btrim(v_item->>'name'), '\s+', ' ', 'g');
      END IF;
      IF v_item ? 'description' THEN
        v_desc := NULLIF(btrim(COALESCE(v_item->>'description', '')), '');
      END IF;
      IF v_item ? 'price' AND v_item->'price' <> 'null'::JSONB THEN
        v_price := (v_item->>'price')::NUMERIC;
      END IF;
      IF v_item ? 'old_price' THEN
        v_old_price := NULLIF(v_item->>'old_price', '')::NUMERIC;
      END IF;
      IF v_item ? 'stock' AND v_item->'stock' <> 'null'::JSONB THEN
        v_stock := (v_item->>'stock')::NUMERIC::INTEGER;
        IF (v_item->>'stock')::NUMERIC <> v_stock THEN
          RAISE EXCEPTION 'Stok tam sayı olmalı' USING ERRCODE = 'P0001';
        END IF;
      END IF;
      IF v_item ? 'category' THEN
        v_category := NULLIF(regexp_replace(btrim(COALESCE(v_item->>'category', '')), '\s+', ' ', 'g'), '');
      END IF;
      IF v_item ? 'image_url' AND NULLIF(btrim(COALESCE(v_item->>'image_url', '')), '') IS NOT NULL THEN
        v_image := btrim(v_item->>'image_url');
      END IF;
      IF v_item ? 'additional_images' THEN
        v_extra := CASE
          WHEN jsonb_typeof(v_item->'additional_images') = 'array' THEN v_item->'additional_images'
          ELSE '[]'::JSONB
        END;
      END IF;
      IF v_item ? 'is_available' AND v_item->'is_available' <> 'null'::JSONB THEN
        v_available := (v_item->>'is_available')::BOOLEAN;
      END IF;
      IF v_item ? 'shipping_fee' THEN
        v_ship_fee := NULLIF(v_item->>'shipping_fee', '')::NUMERIC;
      END IF;
      IF v_item ? 'free_shipping' AND v_item->'free_shipping' <> 'null'::JSONB THEN
        v_free_ship := (v_item->>'free_shipping')::BOOLEAN;
      END IF;
      IF v_item ? 'min_order_quantity' THEN
        v_min_order := NULLIF(v_item->>'min_order_quantity', '')::INTEGER;
      END IF;
      IF v_item ? 'max_order_quantity' THEN
        v_max_order := NULLIF(v_item->>'max_order_quantity', '')::INTEGER;
      END IF;
      IF v_item ? 'badges' THEN
        v_badges := CASE
          WHEN jsonb_typeof(v_item->'badges') = 'array'
            THEN ARRAY(SELECT jsonb_array_elements_text(v_item->'badges'))
          ELSE '{}'::TEXT[]
        END;
      END IF;

      -- ── Doğrulama ────────────────────────────────────────────────────────────
      IF v_name IS NULL OR char_length(v_name) < 2 THEN
        RAISE EXCEPTION 'Ürün adı en az 2 karakter olmalı' USING ERRCODE = 'P0001';
      END IF;
      IF char_length(v_name) > 200 THEN
        RAISE EXCEPTION 'Ürün adı en fazla 200 karakter olabilir' USING ERRCODE = 'P0001';
      END IF;
      IF v_desc IS NOT NULL AND char_length(v_desc) > 5000 THEN
        RAISE EXCEPTION 'Açıklama en fazla 5000 karakter olabilir' USING ERRCODE = 'P0001';
      END IF;
      IF v_category IS NOT NULL AND char_length(v_category) > 60 THEN
        RAISE EXCEPTION 'Kategori adı en fazla 60 karakter olabilir' USING ERRCODE = 'P0001';
      END IF;

      IF v_image IS NOT NULL AND (v_image !~* '^https://' OR char_length(v_image) > 1000) THEN
        RAISE EXCEPTION 'Görsel adresi https:// ile başlamalı' USING ERRCODE = 'P0001';
      END IF;
      IF jsonb_array_length(v_extra) > 4 THEN
        RAISE EXCEPTION 'Ana görsel dışında en fazla 4 görsel eklenebilir' USING ERRCODE = 'P0001';
      END IF;
      FOR v_url IN SELECT jsonb_array_elements_text(v_extra) LOOP
        IF v_url !~* '^https://' OR char_length(v_url) > 1000 THEN
          RAISE EXCEPTION 'Görsel adresi https:// ile başlamalı' USING ERRCODE = 'P0001';
        END IF;
      END LOOP;
      IF v_image IS NULL AND jsonb_array_length(v_extra) > 0 THEN
        v_image := v_extra->>0;
        v_extra := v_extra - 0;
      END IF;

      IF v_type = 'normal' THEN
        -- Güncellemede fiyat gönderilmediyse mevcut (eski kayıtlarda 0 olabilen)
        -- fiyat yüzünden yalnız stok güncellemesi reddedilmesin.
        IF v_price IS NULL OR v_price < 0
           OR (v_price = 0 AND (NOT v_is_update OR v_item ? 'price')) THEN
          RAISE EXCEPTION 'Fiyat 0''dan büyük olmalı' USING ERRCODE = 'P0001';
        END IF;
        IF v_price > 10000000 THEN
          RAISE EXCEPTION 'Fiyat çok yüksek' USING ERRCODE = 'P0001';
        END IF;
        IF v_old_price IS NOT NULL AND v_old_price <= v_price THEN
          IF v_item ? 'old_price' THEN
            RAISE EXCEPTION 'Eski fiyat, satış fiyatından büyük olmalı' USING ERRCODE = 'P0001';
          END IF;
          -- Yalnız fiyat değişti ve eski fiyatın altına inmedi: üstü çizili fiyat
          -- artık anlamsız, temizlenir.
          v_old_price := NULL;
        END IF;
        IF v_stock IS NULL OR v_stock < 0 THEN
          RAISE EXCEPTION 'Stok 0 veya daha büyük bir tam sayı olmalı' USING ERRCODE = 'P0001';
        END IF;
        IF v_free_ship THEN
          v_ship_fee := NULL;
        END IF;
      END IF;

      -- ── GÜNCELLEME ──────────────────────────────────────────────────────────
      IF v_is_update THEN
        UPDATE public.products p
           SET name               = v_name,
               description        = v_desc,
               price              = v_price,
               old_price          = v_old_price,
               stock_quantity     = v_stock,
               category           = v_category,
               image_url          = v_image,
               additional_images  = v_extra,
               is_available       = v_available,
               shipping_fee       = v_ship_fee,
               free_shipping      = v_free_ship,
               min_order_quantity = v_min_order,
               max_order_quantity = v_max_order,
               badges             = v_badges,
               -- Toplu indirimli fiyat yeni fiyatın altında kalmazsa ürün
               -- "indirimli" görünüp pahalı satılırdı (form ile aynı kural).
               discount_price     = CASE
                 WHEN p.discount_price IS NOT NULL AND p.discount_price >= v_price THEN NULL
                 ELSE p.discount_price
               END
         WHERE p.id = v_id;

        v_updated := v_updated + 1;
        v_results := v_results || jsonb_build_object(
          'i', v_idx, 'ok', true, 'action', 'updated', 'id', v_id
        );

      -- ── EKLEME ──────────────────────────────────────────────────────────────
      ELSE
        IF v_type = 'digital' THEN
          v_provider_id  := NULLIF(v_item->>'smm_provider_id', '')::UUID;
          v_service_id   := NULLIF(btrim(COALESCE(v_item->>'smm_service_id', '')), '');
          v_per_1000     := NULLIF(v_item->>'price_per_1000', '')::NUMERIC;
          v_min_qty      := NULLIF(v_item->>'min_quantity', '')::INTEGER;
          v_max_qty      := NULLIF(v_item->>'max_quantity', '')::INTEGER;
          v_max_per_user := NULLIF(v_item->>'max_orders_per_user', '')::INTEGER;

          -- Sağlayıcıyı kullanma kuralı smm-provider-services ile aynı: aktif ve
          -- bu mağazaya ait satıcı sağlayıcısı.
          IF v_provider_id IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.smm_providers sp
             WHERE sp.id = v_provider_id
               AND sp.is_active
               AND sp.owner_type = 'seller'
               AND sp.owner_id = p_shop_id
          ) THEN
            RAISE EXCEPTION 'SMM sağlayıcısı bulunamadı ya da bu mağazaya ait değil'
              USING ERRCODE = 'P0001';
          END IF;
          IF v_service_id IS NULL OR char_length(v_service_id) > 64 THEN
            RAISE EXCEPTION 'Sağlayıcı servis ID geçersiz' USING ERRCODE = 'P0001';
          END IF;
          IF v_per_1000 IS NULL OR v_per_1000 < 0 OR v_per_1000 > 10000000 THEN
            RAISE EXCEPTION '1000 adet fiyatı geçersiz' USING ERRCODE = 'P0001';
          END IF;
          IF v_min_qty IS NULL OR v_max_qty IS NULL OR v_min_qty <= 0 OR v_max_qty < v_min_qty THEN
            RAISE EXCEPTION 'Geçerli min/maks miktar gerekli' USING ERRCODE = 'P0001';
          END IF;
          IF v_max_per_user IS NOT NULL AND v_max_per_user <= 0 THEN
            RAISE EXCEPTION 'Kullanıcı başına sipariş limiti 0''dan büyük olmalı'
              USING ERRCODE = 'P0001';
          END IF;
          IF EXISTS (
            SELECT 1 FROM public.products p
             WHERE p.shop_id = p_shop_id
               AND p.product_type = 'digital'
               AND p.smm_provider_id = v_provider_id
               AND p.smm_service_id = v_service_id
          ) THEN
            RAISE EXCEPTION 'Bu servis mağazanda zaten ürün olarak var'
              USING ERRCODE = 'P0001';
          END IF;

          v_price     := v_per_1000;
          v_old_price := NULL;
          v_stock     := 0;
          v_ship_fee  := NULL;
          v_free_ship := false;
          v_min_order := NULL;
          v_max_order := NULL;
        ELSE
          v_provider_id  := NULL;
          v_service_id   := NULL;
          v_per_1000     := NULL;
          v_min_qty      := NULL;
          v_max_qty      := NULL;
          v_max_per_user := NULL;
        END IF;

        -- Slug: ad → ascii; mağazada varsa kısa rastgele ek.
        v_slug := btrim(regexp_replace(
          lower(translate(v_name, 'çÇğĞıİöÖşŞüÜ', 'cCgGiIoOsSuU')),
          '[^a-z0-9]+', '-', 'g'
        ), '-');
        v_slug := left(COALESCE(NULLIF(v_slug, ''), 'urun'), 80);
        IF EXISTS (
          SELECT 1 FROM public.products p WHERE p.shop_id = p_shop_id AND p.slug = v_slug
        ) THEN
          v_slug := v_slug || '-' || substr(md5(gen_random_uuid()::TEXT), 1, 6);
        END IF;

        INSERT INTO public.products (
          shop_id, name, slug, description, price, old_price, stock_quantity,
          image_url, additional_images, category, is_active, is_available,
          product_type, sizes, shoe_sizes, colors,
          smm_provider_id, smm_service_id, price_per_1000, min_quantity,
          max_quantity, max_orders_per_user,
          badges, shipping_fee, free_shipping,
          min_order_quantity, max_order_quantity
        ) VALUES (
          p_shop_id, v_name, v_slug, v_desc, v_price, v_old_price, v_stock,
          v_image, v_extra, v_category, true, v_available,
          v_type, '[]'::JSONB, '[]'::JSONB, '[]'::JSONB,
          v_provider_id, v_service_id, v_per_1000, v_min_qty,
          v_max_qty, v_max_per_user,
          COALESCE(v_badges, '{}'), v_ship_fee, COALESCE(v_free_ship, false),
          v_min_order, v_max_order
        )
        RETURNING id INTO v_id;

        IF v_type = 'digital'
           AND (NULLIF(v_item->>'provider_rate', '') IS NOT NULL
                OR NULLIF(btrim(COALESCE(v_item->>'service_name', '')), '') IS NOT NULL) THEN
          INSERT INTO public.smm_product_baselines AS b
                 (product_id, provider_rate, service_name, updated_at)
          VALUES (
            v_id,
            NULLIF(v_item->>'provider_rate', '')::NUMERIC,
            NULLIF(btrim(COALESCE(v_item->>'service_name', '')), ''),
            now()
          )
          ON CONFLICT (product_id) DO UPDATE
            SET provider_rate = EXCLUDED.provider_rate,
                service_name  = EXCLUDED.service_name,
                updated_at    = now();
        END IF;

        v_created := v_created + 1;
        v_results := v_results || jsonb_build_object(
          'i', v_idx, 'ok', true, 'action', 'created', 'id', v_id
        );
      END IF;

      -- Satır başarılı: kategorisi mağazada yoksa sona eklenecekler listesine.
      -- (Alt işlem geri alınsa da değişken geri alınmaz; bu yüzden en sonda.)
      -- Güncellemede kategori gönderilmediyse dokunulmaz (satıcının sildiği
      -- bir kategori eski üründen geri gelmesin).
      IF v_item ? 'category' AND v_category IS NOT NULL
         AND NOT (lower(v_category) = ANY (v_cat_keys)) THEN
        v_cat_keys := v_cat_keys || lower(v_category);
        v_new_cats := v_new_cats || v_category;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        v_state      = RETURNED_SQLSTATE,
        v_constraint = CONSTRAINT_NAME,
        v_message    = MESSAGE_TEXT;

      v_failed := v_failed + 1;
      v_results := v_results || jsonb_build_object(
        'i', v_idx,
        'ok', false,
        'code', v_state,
        'error', CASE
          WHEN v_state = 'P0001' THEN v_message
          WHEN v_constraint = 'products_badges_allowed' THEN 'Geçersiz rozet (en fazla 3 rozet)'
          WHEN v_constraint = 'products_order_quantity_valid' THEN 'Min/maks sipariş adedi geçersiz'
          WHEN v_constraint = 'products_shipping_fee_valid' THEN 'Kargo ücreti negatif olamaz'
          WHEN v_constraint = 'positive_price' THEN 'Fiyat negatif olamaz'
          WHEN v_constraint = 'positive_stock' THEN 'Stok negatif olamaz'
          WHEN v_constraint = 'chk_digital_fields' THEN 'Dijital ürün alanları eksik'
          WHEN v_constraint = 'products_max_orders_per_user_check' THEN 'Kullanıcı başına sipariş limiti geçersiz'
          WHEN v_constraint = 'products_shop_id_slug_key' THEN 'Aynı adlı ürün aynı anda eklendi; tekrar deneyin'
          WHEN v_state IN ('22P02', '22003', '22008', '22007') THEN 'Geçersiz sayı, ürün kodu ya da değer'
          ELSE 'Kaydedilemedi'
        END
      );
    END;
  END LOOP;

  IF array_length(v_new_cats, 1) IS NOT NULL THEN
    UPDATE public.shops s
       SET seller_categories = (
             CASE WHEN jsonb_typeof(s.seller_categories) = 'array'
                  THEN s.seller_categories ELSE '[]'::JSONB END
           ) || to_jsonb(v_new_cats)
     WHERE s.id = p_shop_id;
  END IF;

  RETURN jsonb_build_object(
    'created', v_created,
    'updated', v_updated,
    'failed', v_failed,
    'added_categories', to_jsonb(v_new_cats),
    'results', v_results
  );
END;
$fn$;

COMMENT ON FUNCTION public.seller_bulk_upsert_products(UUID, JSONB) IS
  'Satıcı toplu ürün ekleme/güncelleme (dosyadan + SMM servislerinden). Satır başına alt işlem; '
  'en fazla 100 satır. Ayrıntı: 20261015000001_seller_bulk_upsert_products.sql';

REVOKE ALL ON FUNCTION public.seller_bulk_upsert_products(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seller_bulk_upsert_products(UUID, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.seller_bulk_upsert_products(UUID, JSONB) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

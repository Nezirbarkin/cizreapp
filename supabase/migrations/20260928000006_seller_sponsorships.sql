-- =============================================================================
-- 20260928000006_seller_sponsorships.sql
-- -----------------------------------------------------------------------------
-- Görev 3.2 — Satıcı öne çıkarma (Sponsorlu vitrin / doping).
--
-- Satıcı, bakiyesinden ödeyerek dükkanını ya da ürününü seçtiği süre boyunca
-- bir listenin EN ÜSTÜNE, "Sponsor" etiketiyle taşır. Dört vitrin:
--
--   shop_list         Dükkanlar listesi (ana sayfa + Tüm Dükkanlar)
--   shop_category     Dükkanın kategori sayfası
--   product_category  Ürünler sayfası (kategori süzgeci dahil)
--   product_discount  İndirimdeki ürünler (ana sayfa + tümü) — yalnız indirimli ürün
--
-- Paketler (günlük/haftalık, fiyat) `sponsorship_packages`'tadır; varsayılanlar
-- aşağıda tohumlanır, yönetimi admin panelindedir (Görev 4.2). Satın alma
-- `purchase_shop_sponsorship` RPC'siyle: bakiye satırı kilitlenir, düşülür,
-- işlem kaydı yazılır, sponsorluk satırı açılır.
--
-- ## Listeler neye bakar
--
-- Listeler sponsorlu olanı tabloya ayrıca sormaz: `shops`/`products` satırında
-- vitrin başına bir "…_until" sütunu vardır ve satırla birlikte gelir. Süre
-- dolunca kendiliğinden geçersizdir (şimdiyle karşılaştırılır; zamanlayıcı
-- gerekmez). Aynı vitrin için ikinci satın alma öncekinin BİTİŞİNDEN başlar
-- (zincir), sütun zincirin sonunu tutar.
--
-- Bu sütunları YALNIZ satın alma yolu yazar. Satıcı kendi dükkan/ürün
-- satırını güncelleyebildiği için (RLS) istemciden gelen değişiklikler bir
-- tetikleyiciyle sessizce eski değerine döndürülür. Tetikleyici BİLEREK
-- SECURITY INVOKER: DEFINER olsaydı current_user her zaman fonksiyon sahibi
-- olurdu ve koruma hiç çalışmazdı (guard_shop_financial_columns bu yüzden
-- etkisiz — ayrı görev olarak bildirildi).
--
-- ## Onay
--
-- `sponsorship_requires_approval` açıksa satın alma 'pending' olur (ücret
-- alınır, vitrine çıkmaz); onay/ret ve iade Görev 4.2'nin admin ekranındadır.
-- Varsayılan KAPALI: satın alınan anında yayına girer.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Vitrin sütunları (listeler satırla birlikte okur)
-- -----------------------------------------------------------------------------
ALTER TABLE public.shops    ADD COLUMN IF NOT EXISTS sponsored_list_until timestamptz;
ALTER TABLE public.shops    ADD COLUMN IF NOT EXISTS sponsored_category_until timestamptz;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sponsored_category_until timestamptz;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sponsored_discount_until timestamptz;

COMMENT ON COLUMN public.shops.sponsored_list_until IS
  'Ücretli öne çıkarma: dükkan bu zamana kadar dükkanlar listesinin en üstünde (Görev 3.2). Yalnız purchase_shop_sponsorship yazar.';
COMMENT ON COLUMN public.shops.sponsored_category_until IS
  'Ücretli öne çıkarma: dükkan bu zamana kadar kategori sayfasının en üstünde. Yalnız purchase_shop_sponsorship yazar.';
COMMENT ON COLUMN public.products.sponsored_category_until IS
  'Ücretli öne çıkarma: ürün bu zamana kadar Ürünler sayfasının (kategori dahil) en üstünde. Yalnız purchase_shop_sponsorship yazar.';
COMMENT ON COLUMN public.products.sponsored_discount_until IS
  'Ücretli öne çıkarma: ürün bu zamana kadar indirimdeki ürünlerin en üstünde. Yalnız purchase_shop_sponsorship yazar.';

-- -----------------------------------------------------------------------------
-- 2) Paketler
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sponsorship_packages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  placement     text NOT NULL
                CHECK (placement IN ('shop_list', 'shop_category', 'product_category', 'product_discount')),
  name          text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 40),
  duration_days integer NOT NULL CHECK (duration_days BETWEEN 1 AND 90),
  price         numeric(10,2) NOT NULL CHECK (price >= 0),
  is_active     boolean NOT NULL DEFAULT true,
  sort_order    integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sponsorship_packages_placement_duration_key UNIQUE (placement, duration_days)
);

COMMENT ON TABLE public.sponsorship_packages IS
  'Öne çıkarma paketleri (vitrin + süre + fiyat). Satıcı aktif olanları görür; yönetim admin panelinde (Görev 4.2).';

ALTER TABLE public.sponsorship_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sponsorship_packages_read ON public.sponsorship_packages;
CREATE POLICY sponsorship_packages_read ON public.sponsorship_packages
  FOR SELECT TO authenticated
  USING (is_active OR public.auth_is_admin());

DROP POLICY IF EXISTS sponsorship_packages_admin_write ON public.sponsorship_packages;
CREATE POLICY sponsorship_packages_admin_write ON public.sponsorship_packages
  FOR ALL TO authenticated
  USING (public.auth_is_admin())
  WITH CHECK (public.auth_is_admin());

REVOKE ALL ON public.sponsorship_packages FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sponsorship_packages TO authenticated;

-- Varsayılan fiyatlar (TL). Admin panelinden değiştirilir; tekrar
-- çalıştırmak admin'in değiştirdiği fiyatı EZMEZ.
INSERT INTO public.sponsorship_packages (placement, name, duration_days, price, sort_order)
VALUES
  ('shop_list',        'Günlük',   1,  30, 10),
  ('shop_list',        'Haftalık', 7, 150, 20),
  ('shop_category',    'Günlük',   1,  20, 10),
  ('shop_category',    'Haftalık', 7, 100, 20),
  ('product_category', 'Günlük',   1,  15, 10),
  ('product_category', 'Haftalık', 7,  75, 20),
  ('product_discount', 'Günlük',   1,  15, 10),
  ('product_discount', 'Haftalık', 7,  75, 20)
ON CONFLICT (placement, duration_days) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3) Satın alınan öne çıkarmalar
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shop_sponsorships (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id       uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  product_id    uuid REFERENCES public.products(id) ON DELETE CASCADE,
  placement     text NOT NULL
                CHECK (placement IN ('shop_list', 'shop_category', 'product_category', 'product_discount')),
  package_id    uuid REFERENCES public.sponsorship_packages(id) ON DELETE SET NULL,
  -- Paket sonradan değişse/silinse de satın alınan koşul kalır.
  package_name  text NOT NULL,
  duration_days integer NOT NULL CHECK (duration_days BETWEEN 1 AND 90),
  price_paid    numeric(10,2) NOT NULL CHECK (price_paid >= 0),
  status        text NOT NULL DEFAULT 'active'
                CHECK (status IN ('pending', 'active', 'rejected', 'cancelled')),
  starts_at     timestamptz,
  ends_at       timestamptz,
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  reviewed_by   uuid,
  reviewed_at   timestamptz,
  review_note   text,
  CONSTRAINT shop_sponsorships_target_matches_placement
    CHECK ((placement IN ('product_category', 'product_discount')) = (product_id IS NOT NULL)),
  CONSTRAINT shop_sponsorships_active_has_window
    CHECK (status <> 'active' OR (starts_at IS NOT NULL AND ends_at > starts_at))
);

COMMENT ON TABLE public.shop_sponsorships IS
  'Satın alınan öne çıkarmalar (Görev 3.2). Yalnız purchase_shop_sponsorship yazar; satıcı kendi mağazasınınkini okur.';

CREATE INDEX IF NOT EXISTS shop_sponsorships_target_idx
  ON public.shop_sponsorships (shop_id, placement, product_id, ends_at DESC);
CREATE INDEX IF NOT EXISTS shop_sponsorships_status_idx
  ON public.shop_sponsorships (status, created_at DESC);

ALTER TABLE public.shop_sponsorships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shop_sponsorships_owner_read ON public.shop_sponsorships;
CREATE POLICY shop_sponsorships_owner_read ON public.shop_sponsorships
  FOR SELECT TO authenticated
  USING (
    public.auth_is_admin()
    OR EXISTS (
      SELECT 1 FROM public.shops s
       WHERE s.id = shop_sponsorships.shop_id
         AND s.owner_id = (SELECT auth.uid())
    )
  );

-- Yazma politikası YOK: satır yalnız RPC'den açılır (ödeme ile birlikte).
REVOKE ALL ON public.shop_sponsorships FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.shop_sponsorships FROM authenticated;
GRANT SELECT ON public.shop_sponsorships TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) Vitrin sütunlarının koruması (SECURITY INVOKER — bkz. baştaki not)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_shop_sponsorship_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  -- İstemci (PostgREST) değiştiremez; satın alma RPC'si (DEFINER → sahip),
  -- service_role ve bakım bağlamı serbest.
  IF current_user IN ('authenticated', 'anon') THEN
    IF TG_OP = 'INSERT' THEN
      NEW.sponsored_list_until := NULL;
      NEW.sponsored_category_until := NULL;
    ELSE
      NEW.sponsored_list_until := OLD.sponsored_list_until;
      NEW.sponsored_category_until := OLD.sponsored_category_until;
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_shops_guard_sponsorship ON public.shops;
CREATE TRIGGER trg_shops_guard_sponsorship
  BEFORE INSERT OR UPDATE OF sponsored_list_until, sponsored_category_until ON public.shops
  FOR EACH ROW EXECUTE FUNCTION public.guard_shop_sponsorship_columns();

CREATE OR REPLACE FUNCTION public.guard_product_sponsorship_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    IF TG_OP = 'INSERT' THEN
      NEW.sponsored_category_until := NULL;
      NEW.sponsored_discount_until := NULL;
    ELSE
      NEW.sponsored_category_until := OLD.sponsored_category_until;
      NEW.sponsored_discount_until := OLD.sponsored_discount_until;
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_products_guard_sponsorship ON public.products;
CREATE TRIGGER trg_products_guard_sponsorship
  BEFORE INSERT OR UPDATE OF sponsored_category_until, sponsored_discount_until ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.guard_product_sponsorship_columns();

-- -----------------------------------------------------------------------------
-- 5) Vitrin sütununu sponsorluk satırlarından yeniden hesapla
--    (satın alma; ileride onay/iptal — Görev 4.2)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.refresh_sponsored_until(
  p_shop_id uuid,
  p_product_id uuid,
  p_placement text
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_until timestamptz;
BEGIN
  SELECT max(s.ends_at) INTO v_until
    FROM public.shop_sponsorships s
   WHERE s.shop_id = p_shop_id
     AND s.placement = p_placement
     AND s.product_id IS NOT DISTINCT FROM p_product_id
     AND s.status = 'active'
     AND s.ends_at > now();

  CASE p_placement
    WHEN 'shop_list' THEN
      UPDATE public.shops SET sponsored_list_until = v_until WHERE id = p_shop_id;
    WHEN 'shop_category' THEN
      UPDATE public.shops SET sponsored_category_until = v_until WHERE id = p_shop_id;
    WHEN 'product_category' THEN
      UPDATE public.products SET sponsored_category_until = v_until WHERE id = p_product_id;
    WHEN 'product_discount' THEN
      UPDATE public.products SET sponsored_discount_until = v_until WHERE id = p_product_id;
  END CASE;

  RETURN v_until;
END;
$fn$;

REVOKE ALL ON FUNCTION private.refresh_sponsored_until(uuid, uuid, text) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 6) Satın alma
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purchase_shop_sponsorship(
  p_shop_id uuid,
  p_package_id uuid,
  p_product_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_shop record;
  v_pkg record;
  v_product record;
  v_is_product boolean;
  v_target text;
  v_balance_id uuid;
  v_balance numeric(12,2);
  v_status text;
  v_start timestamptz;
  v_end timestamptz;
  v_id uuid := gen_random_uuid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum gerekli' USING ERRCODE = '42501';
  END IF;

  IF NOT COALESCE(
       (SELECT NULLIF(btrim(s.value #>> '{}'), '')::boolean
          FROM public.app_settings s WHERE s.key = 'sponsorship_enabled'),
       true) THEN
    RAISE EXCEPTION 'Öne çıkarma şu anda kapalı'
      USING ERRCODE = 'P0001', HINT = 'disabled';
  END IF;

  -- Mağaza satırı kilitlenir: aynı mağazanın eşzamanlı iki satın alması
  -- zinciri (başlangıç = öncekinin bitişi) bozmasın.
  SELECT s.id, s.owner_id, s.name,
         COALESCE(s.is_active, false) AS is_active,
         COALESCE(s.is_approved, false) AS is_approved
    INTO v_shop
    FROM public.shops s
   WHERE s.id = p_shop_id
   FOR UPDATE;

  IF NOT FOUND OR v_shop.owner_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'Bu mağaza size ait değil' USING ERRCODE = '42501';
  END IF;
  IF NOT v_shop.is_active OR NOT v_shop.is_approved THEN
    RAISE EXCEPTION 'Mağazanız yayında değil; öne çıkarma yalnız onaylı ve açık mağazalarda kullanılabilir'
      USING ERRCODE = 'P0001', HINT = 'shop_not_listed';
  END IF;

  SELECT p.id, p.placement, p.name, p.duration_days, p.price
    INTO v_pkg
    FROM public.sponsorship_packages p
   WHERE p.id = p_package_id AND p.is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Paket bulunamadı' USING ERRCODE = '22023', HINT = 'package_not_found';
  END IF;

  v_is_product := v_pkg.placement IN ('product_category', 'product_discount');

  IF v_is_product THEN
    IF p_product_id IS NULL THEN
      RAISE EXCEPTION 'Öne çıkarılacak ürün seçilmedi' USING ERRCODE = '22023', HINT = 'product_required';
    END IF;
    SELECT pr.id, pr.name,
           COALESCE(pr.is_available, false) AS is_available,
           ((pr.discount_price IS NOT NULL AND pr.discount_price > 0 AND pr.discount_price < pr.price)
             OR (pr.old_price IS NOT NULL AND pr.old_price > pr.price)) AS discounted
      INTO v_product
      FROM public.products pr
     WHERE pr.id = p_product_id AND pr.shop_id = p_shop_id
     FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Ürün bu mağazaya ait değil' USING ERRCODE = '22023', HINT = 'product_not_found';
    END IF;
    IF NOT v_product.is_available THEN
      RAISE EXCEPTION 'Ürün satışta değil' USING ERRCODE = 'P0001', HINT = 'product_unavailable';
    END IF;
    IF v_pkg.placement = 'product_discount' AND NOT COALESCE(v_product.discounted, false) THEN
      RAISE EXCEPTION 'Ürün indirimde değil; bu vitrin yalnız indirimli ürünler içindir'
        USING ERRCODE = 'P0001', HINT = 'product_not_discounted';
    END IF;
    v_target := v_product.name;
  ELSE
    IF p_product_id IS NOT NULL THEN
      RAISE EXCEPTION 'Bu vitrin mağaza içindir, ürün seçilmez' USING ERRCODE = '22023', HINT = 'shop_placement';
    END IF;
    v_target := v_shop.name;
  END IF;

  -- Bakiye: satır kilitlenir, yeterliyse düşülür.
  SELECT ub.id, ub.balance
    INTO v_balance_id, v_balance
    FROM public.user_balances ub
   WHERE ub.user_id = v_uid
   FOR UPDATE;

  IF v_balance_id IS NULL OR v_balance < v_pkg.price THEN
    RAISE EXCEPTION 'Yetersiz bakiye: bu paket % TL', v_pkg.price
      USING ERRCODE = 'P0001', HINT = 'insufficient_balance';
  END IF;

  UPDATE public.user_balances
     SET balance = v_balance - v_pkg.price,
         total_spent = COALESCE(total_spent, 0) + v_pkg.price,
         updated_at = now()
   WHERE id = v_balance_id;

  IF COALESCE(
       (SELECT NULLIF(btrim(s.value #>> '{}'), '')::boolean
          FROM public.app_settings s WHERE s.key = 'sponsorship_requires_approval'),
       false) THEN
    -- Onay bekler: ücret alındı, vitrine onaylanınca çıkar (Görev 4.2).
    v_status := 'pending';
  ELSE
    v_status := 'active';
    -- Zincir: aynı hedef+vitrin için süren/sıradaki son öne çıkarmanın bitişi.
    SELECT GREATEST(now(), COALESCE(max(s.ends_at), now()))
      INTO v_start
      FROM public.shop_sponsorships s
     WHERE s.shop_id = p_shop_id
       AND s.placement = v_pkg.placement
       AND s.product_id IS NOT DISTINCT FROM (CASE WHEN v_is_product THEN p_product_id END)
       AND s.status = 'active'
       AND s.ends_at > now();
    v_end := v_start + make_interval(days => v_pkg.duration_days);
  END IF;

  INSERT INTO public.shop_sponsorships (
    id, shop_id, product_id, placement, package_id, package_name,
    duration_days, price_paid, status, starts_at, ends_at, created_by
  ) VALUES (
    v_id, p_shop_id, CASE WHEN v_is_product THEN p_product_id END, v_pkg.placement,
    v_pkg.id, v_pkg.name, v_pkg.duration_days, v_pkg.price, v_status,
    v_start, v_end, v_uid
  );

  INSERT INTO public.balance_transactions (
    user_id, type, amount, net_amount, balance_before, balance_after,
    reference_type, reference_id, status, description, metadata
  ) VALUES (
    v_uid, 'sponsorship_purchase'::public.balance_transaction_type,
    v_pkg.price, v_pkg.price, v_balance, v_balance - v_pkg.price,
    'shop_sponsorship', v_id, 'completed',
    format('Öne çıkarma — %s (%s): %s',
      CASE v_pkg.placement
        WHEN 'shop_list' THEN 'Dükkanlar listesi'
        WHEN 'shop_category' THEN 'Kategori sayfası'
        WHEN 'product_category' THEN 'Ürünler sayfası'
        ELSE 'İndirimdekiler'
      END,
      v_pkg.name, left(COALESCE(v_target, ''), 120)),
    jsonb_build_object(
      'placement', v_pkg.placement,
      'package_id', v_pkg.id,
      'shop_id', p_shop_id,
      'product_id', CASE WHEN v_is_product THEN p_product_id END,
      'duration_days', v_pkg.duration_days
    )
  );

  IF v_status = 'active' THEN
    PERFORM private.refresh_sponsored_until(
      p_shop_id, CASE WHEN v_is_product THEN p_product_id END, v_pkg.placement);
  END IF;

  RETURN jsonb_build_object(
    'id', v_id,
    'status', v_status,
    'placement', v_pkg.placement,
    'starts_at', v_start,
    'ends_at', v_end,
    'price', v_pkg.price,
    'balance_after', v_balance - v_pkg.price
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.purchase_shop_sponsorship(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_shop_sponsorship(uuid, uuid, uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 7) Ayarlar (admin panelinden yönetilir — Görev 4.2)
-- -----------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('sponsorship_enabled', '"true"',
   'Satıcı öne çıkarma (sponsorlu vitrin) satın alımı açık mı. Kapalıyken süren öne çıkarmalar biter, yenisi alınamaz.'),
  ('sponsorship_requires_approval', '"false"',
   'Öne çıkarma satın alımı admin onayı beklesin mi. Açıksa ücret alınır, vitrine onaylanınca çıkar.')
ON CONFLICT (key) DO NOTHING;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================================
-- Aynı adla ikinci ürün eklenebilsin (2026-10-15)
--
-- products üzerinde UNIQUE (shop_id, slug) var ve slug istemcide üründen
-- (ProductService._generateSlug) üretiliyor: aynı mağazada aynı adla ikinci
-- ürün add_product'ta da, doğrudan INSERT yedeğinde de 23505
-- (products_shop_id_slug_key) ile düşüyordu.
--
-- Kısıt kaldırılmaz (slug mağaza içinde tekil kalsın); onun yerine eklemede
-- çakışan slug'a kısa rastgele ek takılır. Tetikleyici olduğu için tüm ekleme
-- yollarını (add_product, istemci yedeği, seller_bulk_upsert_products, admin)
-- kapsar. Güncelleme slug'a dokunmadığı için yalnız INSERT'te çalışır.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.products_dedupe_slug()
RETURNS TRIGGER
LANGUAGE plpgsql
-- DEFINER: satıcının RLS'le göremediği (ör. pasif) ürünlerin slug'ı da
-- çakışma sayılır; yalnız slug okunur, satır değiştirilmez.
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_base TEXT;
BEGIN
  IF NEW.shop_id IS NULL OR NULLIF(btrim(COALESCE(NEW.slug, '')), '') IS NULL THEN
    RETURN NEW;
  END IF;

  -- Aynı mağazaya aynı slug'la eşzamanlı iki ekleme birbirini görsün.
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.shop_id::TEXT || '/' || NEW.slug, 0));

  v_base := left(NEW.slug, 80);
  WHILE EXISTS (
    SELECT 1 FROM public.products p
     WHERE p.shop_id = NEW.shop_id AND p.slug = NEW.slug
  ) LOOP
    NEW.slug := v_base || '-' || substr(md5(gen_random_uuid()::TEXT), 1, 6);
  END LOOP;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION public.products_dedupe_slug() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_products_dedupe_slug ON public.products;
CREATE TRIGGER trg_products_dedupe_slug
  BEFORE INSERT ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.products_dedupe_slug();

COMMIT;

-- Sınırsız stokta sipariş başına en fazla 2 adet (2026-10-16).
--
-- Satıcı stok girmediyse (stock_unlimited) her müşteri bir siparişte en fazla
-- 2 adet alabilir. Sınır, mevcut "en fazla adet" alanına (max_order_quantity)
-- yazılır; böylece:
--   * order_items tetikleyicisi (enforce_product_order_quantity_limits) ve
--     prepare_checkout_session sınırı her iki ödeme akışında zaten uygular,
--   * ürün sayfası / sepet "En fazla 2 adet alınabilir" der — mağazadaki eski
--     uygulama sürümleri de bu alanı okuduğu için onlarda da geçerli,
--   * satıcı ürün listesinde aynı rozeti görür.
-- Satıcı sınırsız stokta daha KÜÇÜK bir sınır (1) koyabilir; 2'den büyüğü 2'ye
-- indirilir. En az adet 2'yi aşıyorsa en fazlaya eşitlenir (tutarlılık kısıtı).
-- Stok takibe alınınca 2 sınırı kalkar: müşteri stok kadar sepete ekleyebilir
-- (satıcının aynı kayıtta yazdığı farklı bir sınır korunur).

BEGIN;

CREATE OR REPLACE FUNCTION public.products_apply_unlimited_stock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $$
DECLARE
  c_unlimited CONSTANT integer := 999999;
  c_unlimited_max_per_order CONSTANT integer := 2;
BEGIN
  -- Dijital ürünler stok mantığına girmez.
  IF NEW.product_type = 'digital' THEN
    NEW.stock_unlimited := false;
    NEW.stock_quantity := COALESCE(NEW.stock_quantity, 0);
    RETURN NEW;
  END IF;

  IF NEW.stock_quantity IS NULL THEN
    NEW.stock_unlimited := true;
  ELSIF TG_OP = 'UPDATE'
        AND OLD.stock_unlimited
        AND NEW.stock_unlimited
        AND NEW.stock_quantity IS DISTINCT FROM OLD.stock_quantity
        AND NEW.stock_quantity <> c_unlimited THEN
    -- Sınırsız ürüne gerçek bir stok yazıldı → artık stok takipli.
    NEW.stock_unlimited := false;
  END IF;

  -- Sınırsızdan stoklu ürüne geçiş: sınırsızlığın getirdiği 2 adet sınırı
  -- kalkar (müşteri stok kadar alabilir). Satıcı aynı kayıtta başka bir sınır
  -- yazdıysa o korunur.
  IF TG_OP = 'UPDATE'
     AND OLD.stock_unlimited
     AND NOT NEW.stock_unlimited
     AND NEW.max_order_quantity IS NOT DISTINCT FROM OLD.max_order_quantity
     AND NEW.max_order_quantity = c_unlimited_max_per_order THEN
    NEW.max_order_quantity := NULL;
  END IF;

  IF NEW.stock_unlimited THEN
    NEW.stock_quantity := c_unlimited;
    NEW.max_order_quantity := LEAST(
      COALESCE(NEW.max_order_quantity, c_unlimited_max_per_order),
      c_unlimited_max_per_order
    );
    IF NEW.min_order_quantity IS NOT NULL
       AND NEW.min_order_quantity > NEW.max_order_quantity THEN
      NEW.min_order_quantity := NEW.max_order_quantity;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.products_apply_unlimited_stock() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_products_apply_unlimited_stock ON public.products;
CREATE TRIGGER trg_products_apply_unlimited_stock
  BEFORE INSERT OR UPDATE OF stock_quantity, stock_unlimited, product_type,
                             min_order_quantity, max_order_quantity
  ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.products_apply_unlimited_stock();

-- Göçten önce sınırsız yapılmış ürünler (tetikleyici yeniden hesaplar).
UPDATE public.products
   SET max_order_quantity = max_order_quantity
 WHERE stock_unlimited
   AND (max_order_quantity IS NULL OR max_order_quantity > 2);

COMMIT;

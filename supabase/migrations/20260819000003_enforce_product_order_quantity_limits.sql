-- ============================================================================
-- 2026-08-19 | Satici siparis adedi limitini CANLI siparis yolunda da zorla
-- ============================================================================
-- products.min_order_quantity / max_order_quantity dogrulamasi
-- private.prepare_checkout_session icine eklendi; ancak uygulamanin AKTIF
-- odeme akisi (lib/features/shop/services/order_service.dart) o RPC'yi
-- kullanmiyor, dogrudan orders + order_items INSERT ediyor. Yani limit
-- yalnizca RPC yolunda zorlanmis olurdu ve pratikte istemci tarafi bir
-- oneriden ibaret kalirdi.
--
-- Bu trigger limiti veritabani seviyesinde, hangi yoldan gelirse gelsin
-- uygular. Limit tanimlanmamis urunlerde (her iki kolon da NULL - mevcut
-- TUM urunler boyle) trigger hicbir sey yapmaz, dolayisiyla mevcut siparis
-- akisinin davranisi DEGISMEZ.
--
-- Dijital urunler kapsam disidir: onlarda miktar araligi
-- products.min_quantity / max_quantity ile ayrica yonetiliyor.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_product_order_quantity_limits()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_product RECORD;
BEGIN
  IF NEW.product_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT p.name, p.product_type, p.min_order_quantity, p.max_order_quantity
    INTO v_product
  FROM public.products p
  WHERE p.id = NEW.product_id;

  -- Urun bulunamadiysa (ya da silinmisse) bu trigger'in isi degil; mevcut
  -- foreign key / uygulama mantigi ne yapiyorsa o gecerli.
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF COALESCE(v_product.product_type, 'normal') = 'digital' THEN
    RETURN NEW;
  END IF;

  IF v_product.min_order_quantity IS NOT NULL
     AND NEW.quantity < v_product.min_order_quantity THEN
    RAISE EXCEPTION 'Bu urun icin en az % adet siparis verilebilir: %',
      v_product.min_order_quantity, v_product.name
      USING ERRCODE = 'P0001';
  END IF;

  IF v_product.max_order_quantity IS NOT NULL
     AND NEW.quantity > v_product.max_order_quantity THEN
    RAISE EXCEPTION 'Bu urun icin en fazla % adet siparis verilebilir: %',
      v_product.max_order_quantity, v_product.name
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_enforce_product_order_quantity_limits
  ON public.order_items;

CREATE TRIGGER trg_enforce_product_order_quantity_limits
  BEFORE INSERT OR UPDATE OF quantity ON public.order_items
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_product_order_quantity_limits();

COMMIT;

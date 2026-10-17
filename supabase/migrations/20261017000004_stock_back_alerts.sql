-- ============================================================================
-- "Stoğa gelince haber ver" (2026-10-17)
-- ----------------------------------------------------------------------------
-- Tükenen ürünün detayında kullanıcı bekleme listesine girer; ürün yeniden
-- satılabilir olduğunda (stok 0 → >0, is_available false → true, sınırsız
-- stok açıldı) bekleyenlere bir kez 'stock_back' bildirimi gider ve kayıtları
-- silinir. Fiyat alarmı (price_alerts / notify_price_drops) ile aynı desen.
--
-- Satılabilirlik istemcideki Product.inStock ile aynı:
--   (dijital VEYA sınırsız stok VEYA stock_quantity > 0) VE is_available
-- Bildirim tekrarı: notifications.dedup_notification aynı (kullanıcı, ürün,
-- tür) eski satırı silip yenisini yazar.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.stock_alerts (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id uuid        NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT stock_alerts_user_product_key UNIQUE (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_stock_alerts_product_id ON public.stock_alerts (product_id);

ALTER TABLE public.stock_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS stock_alerts_select_own ON public.stock_alerts;
CREATE POLICY stock_alerts_select_own ON public.stock_alerts
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS stock_alerts_insert_own ON public.stock_alerts;
CREATE POLICY stock_alerts_insert_own ON public.stock_alerts
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS stock_alerts_delete_own ON public.stock_alerts;
CREATE POLICY stock_alerts_delete_own ON public.stock_alerts
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

REVOKE ALL ON public.stock_alerts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.stock_alerts TO authenticated;

CREATE OR REPLACE FUNCTION private.notify_stock_back()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_was_sellable boolean;
  v_is_sellable  boolean;
BEGIN
  v_was_sellable := COALESCE(OLD.is_available, true) AND (
    OLD.product_type = 'digital'
    OR COALESCE(OLD.stock_unlimited, false)
    OR COALESCE(OLD.stock_quantity, 0) > 0
  );
  v_is_sellable := COALESCE(NEW.is_available, true) AND (
    NEW.product_type = 'digital'
    OR COALESCE(NEW.stock_unlimited, false)
    OR COALESCE(NEW.stock_quantity, 0) > 0
  );

  IF v_was_sellable OR NOT v_is_sellable THEN
    RETURN NEW;
  END IF;

  BEGIN
    INSERT INTO public.notifications (
      user_id, type, title, content, entity_id, entity_type, entity_image, data, is_read
    )
    SELECT
      a.user_id,
      'stock_back',
      '📦 Beklediğin ürün stokta!',
      format('%s yeniden satışta. Tükenmeden sepetine ekle.', NEW.name),
      NEW.id::text,
      'product',
      NEW.image_url,
      jsonb_build_object('product_id', NEW.id, 'shop_id', NEW.shop_id),
      false
    FROM public.stock_alerts a
    WHERE a.product_id = NEW.id;

    DELETE FROM public.stock_alerts WHERE product_id = NEW.id;
  EXCEPTION WHEN OTHERS THEN
    -- Bildirim hatası satıcının stok güncellemesini ASLA geri almasın.
    RAISE LOG 'notify_stock_back (%): %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.notify_stock_back() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_products_notify_stock_back ON public.products;
CREATE TRIGGER trg_products_notify_stock_back
  AFTER UPDATE OF stock_quantity, is_available, stock_unlimited ON public.products
  FOR EACH ROW EXECUTE FUNCTION private.notify_stock_back();

COMMIT;

NOTIFY pgrst, 'reload schema';

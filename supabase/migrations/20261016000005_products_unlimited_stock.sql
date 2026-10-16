-- Sınırsız stok + stok tükenince satıcıya bildirim (2026-10-16).
--
-- Kural:
--   * Satıcı stok alanını BOŞ bırakırsa ürün stoğu sınırsızdır
--     (`stock_unlimited = true`). İstemci boş alanı `stock_quantity = NULL`
--     olarak yazar; tetikleyici bunu bayrağa çevirir.
--   * Sınırsız üründe `stock_quantity` 999999'a sabitlenir. Mağazadaki eski
--     uygulama sürümleri bayrağı bilmez, `stock_quantity > 0` ile "stokta"
--     der; sabit değer sayesinde sınırsız ürünü "Tükendi" göstermezler ve
--     sepet/ödeme stok kontrolleri (prepare_checkout_session vb.) değişmeden
--     geçer.
--   * Sınırsız ürüne 999999 dışında bir stok yazılırsa (eski satıcı uygulaması,
--     toplu yükleme, yönetici) satıcı stoğu elle belirlemiş demektir → bayrak
--     kapanır. Bu yüzden sipariş onayı / iptali sınırsız ürünün stoğuna HİÇ
--     dokunmaz (aksi halde 999999 → 999998 bayrağı kapatırdı).
--   * Satıcı stok girip stok siparişlerle 0'a inerse ürün "Tükendi" olur
--     (istemci zaten stock_quantity = 0'ı tükendi gösterir) ve satıcıya
--     `seller_product_out_of_stock` bildirimi gider. Satıcının kendisinin 0
--     yazması bildirim üretmez (bildirim yalnız sipariş onayındaki düşüşten).

BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS stock_unlimited boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.products.stock_unlimited IS
  'true = stok takibi yok (satıcı stok girmedi). stock_quantity bu durumda 999999 sabitidir.';

-- ── 1) Bayrak / sabit değer tutarlılığı ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.products_apply_unlimited_stock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $$
DECLARE
  c_unlimited CONSTANT integer := 999999;
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

  IF NEW.stock_unlimited THEN
    NEW.stock_quantity := c_unlimited;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.products_apply_unlimited_stock() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_products_apply_unlimited_stock ON public.products;
CREATE TRIGGER trg_products_apply_unlimited_stock
  BEFORE INSERT OR UPDATE OF stock_quantity, stock_unlimited, product_type ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.products_apply_unlimited_stock();

-- ── 2) Stok tükendi → satıcıya bildirim ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_seller_product_out_of_stock(p_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_owner uuid;
  v_shop_id uuid;
  v_name text;
  v_image text;
BEGIN
  SELECT s.owner_id, p.shop_id, p.name, p.image_url
    INTO v_owner, v_shop_id, v_name, v_image
    FROM public.products p
    JOIN public.shops s ON s.id = p.shop_id
   WHERE p.id = p_product_id;
  IF v_owner IS NULL THEN RETURN; END IF;

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, entity_image, data)
  VALUES (
    v_owner,
    'seller_product_out_of_stock',
    'Stok tükendi',
    COALESCE(NULLIF(v_name, ''), 'Bir ürününüz') ||
      ' ürününün stoğu bitti; müşteriler artık "Tükendi" görüyor. ' ||
      'Satışa devam etmek için Ürünlerim''den stok ekleyin.',
    p_product_id::text,
    'product',
    v_image,
    jsonb_build_object('product_id', p_product_id, 'shop_id', v_shop_id)
  );
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'notify_seller_product_out_of_stock failed for product %: %', p_product_id, SQLERRM;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_seller_product_out_of_stock(uuid) FROM PUBLIC, anon, authenticated;

-- ── 3) Sipariş onayı: sınırsız ürün stoğu düşmez, 0'a inince bildirim ──────
CREATE OR REPLACE FUNCTION public.decrease_product_stock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order_item RECORD;
  v_product RECORD;
  v_new_stock integer;
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN
    FOR v_order_item IN
      SELECT product_id, quantity, flash_sale_id
      FROM order_items
      WHERE order_id = NEW.id
    LOOP
      -- Satır kilidiyle güncel stoğu oku (eşzamanlı onaylarda yarış durumunu önler).
      SELECT stock_quantity, stock_unlimited, name INTO v_product
      FROM products
      WHERE id = v_order_item.product_id
      FOR UPDATE;

      -- Sınırsız stoklu ürün: kontrol de düşüş de yok.
      CONTINUE WHEN COALESCE(v_product.stock_unlimited, false);

      IF v_order_item.flash_sale_id IS NULL
         AND v_product.stock_quantity IS NOT NULL
         AND v_product.stock_quantity < v_order_item.quantity THEN
        RAISE EXCEPTION 'Yetersiz stok: "%" için % adet mevcut, % adet talep edildi',
          v_product.name, v_product.stock_quantity, v_order_item.quantity;
      END IF;

      v_new_stock := NULL;
      UPDATE products
      SET stock_quantity = stock_quantity - v_order_item.quantity
      WHERE id = v_order_item.product_id
        AND stock_quantity IS NOT NULL
        AND NOT stock_unlimited
      RETURNING stock_quantity INTO v_new_stock;

      IF v_new_stock IS NOT NULL
         AND v_new_stock <= 0
         AND v_product.stock_quantity > 0 THEN
        PERFORM public.notify_seller_product_out_of_stock(v_order_item.product_id);
      END IF;

      RAISE NOTICE 'Stok düşürüldü: Product ID: %, Miktar: %', v_order_item.product_id, v_order_item.quantity;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$;

-- ── 4) İptal: sınırsız ürünün stoğuna dokunma ─────────────────────────────
CREATE OR REPLACE FUNCTION public.restore_product_stock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_order_item RECORD;
BEGIN
  -- Sipariş "confirmed"dan "cancelled"a geçtiğinde stokları geri yükle
  IF OLD.status = 'confirmed' AND NEW.status = 'cancelled' THEN
    FOR v_order_item IN
      SELECT product_id, quantity
      FROM order_items
      WHERE order_id = NEW.id
    LOOP
      -- Ürün stoğunu geri yükle (sınırsız stoklu ürün hariç)
      UPDATE products
      SET stock_quantity = stock_quantity + v_order_item.quantity
      WHERE id = v_order_item.product_id
        AND NOT stock_unlimited;

      RAISE NOTICE 'Stok geri yüklendi: Product ID: %, Miktar: %', v_order_item.product_id, v_order_item.quantity;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';

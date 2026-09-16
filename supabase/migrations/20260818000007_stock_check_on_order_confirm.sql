-- Sipariş onaylanırken (status -> 'confirmed') stok yetersizse sessizce
-- 0'a sabitlemek yerine onayı engelle.
--
-- ESKİ DAVRANIŞ: decrease_product_stock() `GREATEST(stock_quantity - qty, 0)`
-- kullanıyordu; stok yetersiz olsa bile UPDATE her zaman başarılı oluyor,
-- admin/mağaza panelinden fazla satış (oversell) yapılabiliyor ve bunun
-- hiçbir izi/hatası kalmıyordu.
--
-- YENİ DAVRANIŞ: `stock_quantity IS NOT NULL` (stok takibi açık) VE talep
-- edilen miktar mevcut stoktan fazlaysa RAISE EXCEPTION ile tüm UPDATE
-- (ve dolayısıyla siparişin 'confirmed' olması) geri alınır; sipariş
-- 'pending' durumunda kalır. Flaş satış satırları (`flash_sale_id IS NOT
-- NULL`) hariç tutulur çünkü onların stoğu ayrı bir mekanizmayla
-- (claim_flash_sale/release_flash_sale, flash_sale_reservations) zaten
-- yönetiliyor, `products.stock_quantity`'yi etkilemiyor.

CREATE OR REPLACE FUNCTION decrease_product_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_item RECORD;
  v_product RECORD;
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN
    FOR v_order_item IN
      SELECT product_id, quantity, flash_sale_id
      FROM order_items
      WHERE order_id = NEW.id
    LOOP
      -- Satır kilidiyle güncel stoğu oku (eşzamanlı onaylarda yarış durumunu önler).
      SELECT stock_quantity, name INTO v_product
      FROM products
      WHERE id = v_order_item.product_id
      FOR UPDATE;

      IF v_order_item.flash_sale_id IS NULL
         AND v_product.stock_quantity IS NOT NULL
         AND v_product.stock_quantity < v_order_item.quantity THEN
        RAISE EXCEPTION 'Yetersiz stok: "%" için % adet mevcut, % adet talep edildi',
          v_product.name, v_product.stock_quantity, v_order_item.quantity;
      END IF;

      UPDATE products
      SET stock_quantity = stock_quantity - v_order_item.quantity
      WHERE id = v_order_item.product_id
        AND stock_quantity IS NOT NULL;

      RAISE NOTICE 'Stok düşürüldü: Product ID: %, Miktar: %', v_order_item.product_id, v_order_item.quantity;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION decrease_product_stock() IS 'Sipariş onaylandığında (status=confirmed) ürün stoklarını düşürür; yetersiz stokta onayı reddeder (flaş satış satırları hariç).';

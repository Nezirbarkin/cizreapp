-- Sipariş Onaylandığında Stok Düşürme Sistemi
-- Status "confirmed" olduğunda order_items'deki ürünlerin stoklarını düşürür

-- Stok düşürme fonksiyonu
CREATE OR REPLACE FUNCTION decrease_product_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_item RECORD;
BEGIN
  -- Sadece sipariş "confirmed" durumuna geçtiğinde çalış
  IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN
    -- Bu siparişin tüm ürünlerini al ve stokları düşür
    FOR v_order_item IN 
      SELECT product_id, quantity 
      FROM order_items 
      WHERE order_id = NEW.id
    LOOP
      -- Ürün stoğunu düşür
      UPDATE products
      SET stock_quantity = GREATEST(stock_quantity - v_order_item.quantity, 0)
      WHERE id = v_order_item.product_id;
      
      -- Log için debug print
      RAISE NOTICE 'Stok düşürüldü: Product ID: %, Miktar: %', v_order_item.product_id, v_order_item.quantity;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Trigger: Sipariş statusu değiştiğinde çalışır
DROP TRIGGER IF EXISTS trigger_decrease_stock_on_order_confirm ON orders;
CREATE TRIGGER trigger_decrease_stock_on_order_confirm
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION decrease_product_stock();

-- Stok geri yükleme fonksiyonu (sipariş iptal edildiğinde)
CREATE OR REPLACE FUNCTION restore_product_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
      -- Ürün stoğunu geri yükle
      UPDATE products
      SET stock_quantity = stock_quantity + v_order_item.quantity
      WHERE id = v_order_item.product_id;
      
      RAISE NOTICE 'Stok geri yüklendi: Product ID: %, Miktar: %', v_order_item.product_id, v_order_item.quantity;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Trigger: Sipariş iptal edildiğinde çalışır
DROP TRIGGER IF EXISTS trigger_restore_stock_on_order_cancel ON orders;
CREATE TRIGGER trigger_restore_stock_on_order_cancel
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION restore_product_stock();

-- Comment
COMMENT ON FUNCTION decrease_product_stock() IS 'Sipariş onaylandığında (status=confirmed) ürün stoklarını otomatik düşürür';
COMMENT ON FUNCTION restore_product_stock() IS 'Sipariş iptal edildiğinde (cancelled) ürün stoklarını geri yükler';

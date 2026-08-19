-- ================================================================
-- Pasif Satıcı Ürünlerini Gizle
-- ================================================================
-- Bu migration, pasif satıcıların ürünlerinin müşterilere gösterilmemesini sağlar

-- 1. Aktif olmayan satıcıların ürünlerini pasif yap (trigger)
CREATE OR REPLACE FUNCTION public.sync_shop_products_availability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Eğer shop pasife alındıysa (is_active = false)
  IF NEW.is_active = FALSE AND OLD.is_active = TRUE THEN
    -- Bu satıcının tüm ürünlerini pasif yap
    UPDATE products
    SET is_available = FALSE
    WHERE shop_id = NEW.id;
    
    RAISE NOTICE 'Shop % pasife alındı, % ürün pasif edildi', NEW.id, (
      SELECT COUNT(*) FROM products WHERE shop_id = NEW.id
    );
  
  -- Eğer shop aktif hale getirildiyse (is_active = true)
  ELSIF NEW.is_active = TRUE AND OLD.is_active = FALSE THEN
    -- Bu satıcının tüm ürünlerini aktif yap
    UPDATE products
    SET is_available = TRUE
    WHERE shop_id = NEW.id;
    
    RAISE NOTICE 'Shop % aktif edildi, % ürün aktif edildi', NEW.id, (
      SELECT COUNT(*) FROM products WHERE shop_id = NEW.id
    );
  END IF;
  
  RETURN NEW;
END;
$$;

-- 2. Trigger'ı shops tablosuna ekle
DROP TRIGGER IF EXISTS sync_shop_products_availability_trigger ON shops;
CREATE TRIGGER sync_shop_products_availability_trigger
  AFTER UPDATE OF is_active ON shops
  FOR EACH ROW
  EXECUTE FUNCTION sync_shop_products_availability();

-- 3. Mevcut pasif satıcıların ürünlerini pasif yap (bir kerelik)
UPDATE products p
SET is_available = FALSE
FROM shops s
WHERE p.shop_id = s.id
  AND s.is_active = FALSE
  AND p.is_available = TRUE;

-- Yorum ekle
COMMENT ON FUNCTION public.sync_shop_products_availability() IS 'Satıcı pasif/aktif edildiğinde ürünlerini otomatik olarak pasif/aktif eder';
COMMENT ON TRIGGER sync_shop_products_availability_trigger ON shops IS 'Satıcı durumu değiştiğinde ürün durumlarını senkronize eder';

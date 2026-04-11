-- Sipariş ID'lerini 1'den başlatmak için sequence ve trigger oluştur

-- 1. Sequence oluştur (1'den başlasın)
CREATE SEQUENCE IF NOT EXISTS order_number_seq START WITH 1;

-- 2. orders tablosuna order_number_int kolonu ekle (eğer yoksa)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_number_int INTEGER;

-- 3. Trigger function: Her yeni sipariş eklendiğinde otomatik order_number_int ata
CREATE OR REPLACE FUNCTION set_order_number_int()
RETURNS TRIGGER AS $$
BEGIN
  -- Eğer order_number_int henüz atanmadıysa, sequence'den al
  IF NEW.order_number_int IS NULL THEN
    NEW.order_number_int := nextval('order_number_seq');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Trigger oluştur (eğer yoksa)
DROP TRIGGER IF EXISTS trigger_set_order_number_int ON orders;
CREATE TRIGGER trigger_set_order_number_int
  BEFORE INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION set_order_number_int();

-- 5. Mevcut siparişlere sıralı ID ata (opsiyonel - sadece ilk defa çalıştırılmalı)
-- Eğer mevcut siparişler varsa ve order_number_int'leri yoksa:
UPDATE orders 
SET order_number_int = sub.row_num
FROM (
  SELECT id, ROW_NUMBER() OVER (ORDER BY created_at) as row_num
  FROM orders
  WHERE order_number_int IS NULL
) sub
WHERE orders.id = sub.id;

-- 6. Sequence'i mevcut en yüksek değerden devam ettir
SELECT setval('order_number_seq', COALESCE((SELECT MAX(order_number_int) FROM orders), 0) + 1, false);

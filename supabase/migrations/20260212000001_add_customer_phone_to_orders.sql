-- Orders tablosuna customer_phone sütunu ekle
-- Müşterinin sipariş sırasında girdiği telefon numarasını saklamak için

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS customer_phone TEXT;

-- Comment ekle
COMMENT ON COLUMN orders.customer_phone IS 'Müşteri telefon numarası - sipariş sırasında kaydedilir';

-- Mevcut siparişler için profiles tablosundan phone çekmeyi dene (optional - RLS bypass ile)
UPDATE orders 
SET customer_phone = (
  SELECT phone FROM profiles WHERE profiles.id = orders.user_id
)
WHERE customer_phone IS NULL AND user_id IS NOT NULL;

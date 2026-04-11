-- Satıcıların kendi kuryelerinin olup olmadığını belirten alan
-- Kuryesi olan satıcılar kendi teslimat ücretlerini belirler
-- Kuryesi olmayan satıcıların teslimatını admin'in kuryeleri yapar

-- has_own_courier alanını ekle (varsayılan false)
ALTER TABLE shops 
ADD COLUMN IF NOT EXISTS has_own_courier BOOLEAN DEFAULT false;

-- Mevcut satıcılar için delivery_fee varsa has_own_courier'i true yap
UPDATE shops 
SET has_own_courier = true 
WHERE delivery_fee IS NOT NULL AND delivery_fee > 0;

-- Yorum ekle
COMMENT ON COLUMN shops.has_own_courier IS 'Satıcının kendi kuryesi var mı? True ise kendi teslimat ücretini belirler, false ise admin belirler';
COMMENT ON COLUMN shops.delivery_fee IS 'Satıcının kendi belirlediği teslimat ücreti (sadece has_own_courier=true ise kullanılır)';

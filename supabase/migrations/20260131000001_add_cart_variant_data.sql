-- Cart tablosuna varyant verisi (renk, beden, numara) için alan ekle
ALTER TABLE cart
ADD COLUMN IF NOT EXISTS variant_data JSONB DEFAULT NULL;

COMMENT ON COLUMN cart.variant_data IS 'Ürün varyant bilgileri: {"color": "Kırmızı", "size": "M", "shoeSize": "42"}';

-- İndeks ekle - varyant bazlı sorgulamalar için
CREATE INDEX IF NOT EXISTS idx_cart_variant_data ON cart USING GIN (variant_data);

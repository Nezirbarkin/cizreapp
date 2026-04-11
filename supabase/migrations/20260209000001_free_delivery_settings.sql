-- Ücretsiz teslimat için minimum tutar ve teslimat süresi
-- Dükkan ayarlarında bu bilgilerin gösterilmesi için

ALTER TABLE shops
ADD COLUMN IF NOT EXISTS free_delivery_min_amount NUMERIC DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS delivery_time VARCHAR(50);

-- Varsayılan değerler açıklama
-- free_delivery_min_amount: Bu tutar ve üzeri siparişlerde teslimat ücretsiz
-- delivery_time: Örn: "30-45 dk", "1-2 saat", "Aynı gün"

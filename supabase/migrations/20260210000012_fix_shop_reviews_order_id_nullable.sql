-- shop_reviews tablosunda order_id sütununu nullable yap
-- Sorun: order_id NOT NULL constraint'i var ama bazı yorum senaryolarında
-- (örn: mağaza detay sayfasından yorum) orderId gönderilmiyor
-- Hata: "null value in column order_id of relation shop_reviews violates not-null constraint"

-- order_id sütununu nullable yap
ALTER TABLE shop_reviews ALTER COLUMN order_id DROP NOT NULL;

-- order_id NULL olabilir, bu yüzden default değer de NULL olsun
ALTER TABLE shop_reviews ALTER COLUMN order_id SET DEFAULT NULL;

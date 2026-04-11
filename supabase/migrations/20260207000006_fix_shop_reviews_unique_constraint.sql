-- shop_reviews_legacy_unique constraint sorunu
-- Problem: Aynı kullanıcı aynı mağazaya birden fazla sipariş verdiğinde hata veriyor
-- Çözüm: legacy_unique index'i kaldır, ama order_id NULL kalabilsin (eski kayıtlarla uyumlu)

-- 1. Legacy unique index'i kaldır (sorun kaynağı)
DROP INDEX IF EXISTS shop_reviews_legacy_unique;

-- 2. Eski sistem ile uyumlu kalması için:
-- order_id NULL olabilir (eski yorumlar)
-- VEYA order_id ile yeni yorumlar (siparişe bağlı)

-- Mevcut unique constraint'i kontrol et
DROP INDEX IF EXISTS shop_reviews_order_unique;

-- Yeni yapı: 
-- - Aynı siparişe sadece 1 yorum (order_id NOT NULL olduğunda)
-- - Eski NULL kayıtlar kalmaya devam etsin
CREATE UNIQUE INDEX IF NOT EXISTS shop_reviews_order_unique
ON shop_reviews(shop_id, user_id, order_id)
WHERE order_id IS NOT NULL;

-- Eski sistemle uyumlu: order_id NULL olabilir
-- Yeni sistem: Tüm yorum order_id ile beraber oluşturulur
-- Result: Aynı kullanıcı aynı mağazaya
-- - Eski NULL yorum: 1 tane (legacy)
-- - Yeni order_id'li yorumlar: Her sipariş için 1 tane

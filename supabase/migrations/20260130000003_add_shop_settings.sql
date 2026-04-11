-- Mağaza Ayarları için shops tablosu güncellemeleri
-- Logo, arka plan resmi, çalışma saatleri ve diğer ayarlar

-- 1. Mevcut kolonları kontrol et ve ekle (IF NOT EXISTS ile)
ALTER TABLE shops 
ADD COLUMN IF NOT EXISTS logo_url TEXT,
ADD COLUMN IF NOT EXISTS cover_image TEXT,
ADD COLUMN IF NOT EXISTS phone VARCHAR(20),
ADD COLUMN IF NOT EXISTS address TEXT,
ADD COLUMN IF NOT EXISTS description TEXT,
ADD COLUMN IF NOT EXISTS working_hours JSONB DEFAULT '{"monday":{"open":"09:00","close":"18:00","active":true},"tuesday":{"open":"09:00","close":"18:00","active":true},"wednesday":{"open":"09:00","close":"18:00","active":true},"thursday":{"open":"09:00","close":"18:00","active":true},"friday":{"open":"09:00","close":"18:00","active":true},"saturday":{"open":"09:00","close":null,"active":true},"sunday":{"open":null,"close":null,"active":false}}'::jsonb,
ADD COLUMN IF NOT EXISTS min_order_amount DECIMAL(12, 2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS free_delivery_threshold DECIMAL(12, 2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS delivery_time VARCHAR(50) DEFAULT '30-45 dakika',
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS rating DECIMAL(3, 2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS review_count INTEGER DEFAULT 0;

-- 2. Index'ler
CREATE INDEX IF NOT EXISTS idx_shops_is_active ON shops(is_active);
CREATE INDEX IF NOT EXISTS idx_shops_is_verified ON shops(is_verified);
CREATE INDEX IF NOT EXISTS idx_shops_rating ON shops(rating DESC);

-- 3. Yorumlar
COMMENT ON COLUMN shops.logo_url IS 'Mağaza logolu URL''si';
COMMENT ON COLUMN shops.cover_image IS 'Mağaza kapak/arka plan resmi URL''si';
COMMENT ON COLUMN shops.phone IS 'Mağaza telefon numarası';
COMMENT ON COLUMN shops.address IS 'Mağaza adresi';
COMMENT ON COLUMN shops.description IS 'Mağaza açıklaması';
COMMENT ON COLUMN shops.working_hours IS 'Çalışma saatleri JSON formatında (her gün için açık/kapış saati)';
COMMENT ON COLUMN shops.min_order_amount IS 'Minimum sipariş tutarı';
COMMENT ON COLUMN shops.free_delivery_threshold IS 'Ücretsiz teslimat için minimum sipariş tutarı';
COMMENT ON COLUMN shops.delivery_time IS 'Tahmini teslimat süresi (örn: 30-45 dakika)';
COMMENT ON COLUMN shops.is_active IS 'Mağaza aktif mi? (pasif mağazalar gösterilmez)';
COMMENT ON COLUMN shops.is_verified IS 'Mağaza doğrulanmış mı?';
COMMENT ON COLUMN shops.rating IS 'Mağaza puanı (0-5 arası)';
COMMENT ON COLUMN shops.review_count IS 'Toplam yorum sayısı';

-- 4. working_hours varsayılan değer güncelleme fonksiyonu
CREATE OR REPLACE FUNCTION set_default_working_hours()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.working_hours IS NULL THEN
    NEW.working_hours = '{"monday":{"open":"09:00","close":"18:00","active":true},"tuesday":{"open":"09:00","close":"18:00","active":true},"wednesday":{"open":"09:00","close":"18:00","active":true},"thursday":{"open":"09:00","close":"18:00","active":true},"friday":{"open":"09:00","close":"18:00","active":true},"saturday":{"open":"09:00","close":null,"active":true},"sunday":{"open":null,"close":null,"active":false}}'::jsonb;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Trigger
DROP TRIGGER IF EXISTS set_default_working_hours_trigger ON shops;
CREATE TRIGGER set_default_working_hours_trigger
BEFORE INSERT ON shops
FOR EACH ROW
EXECUTE FUNCTION set_default_working_hours();

-- 6. Mağaza durumunu güncelleme fonksiyonu (rating güncellemesi için)
CREATE OR REPLACE FUNCTION update_shop_rating()
RETURNS TRIGGER AS $$
BEGIN
  -- Mağaza yorum sayısı ve ortalama puanını güncelle
  UPDATE shops
  SET 
    review_count = (
      SELECT COUNT(*) 
      FROM shop_reviews 
      WHERE shop_id = NEW.shop_id AND is_deleted = false
    ),
    rating = COALESCE((
      SELECT AVG(rating) 
      FROM shop_reviews 
      WHERE shop_id = NEW.shop_id AND is_deleted = false
    ), 0)
  WHERE id = NEW.shop_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7. Review trigger
DROP TRIGGER IF EXISTS update_shop_rating_trigger ON shop_reviews;
CREATE TRIGGER update_shop_rating_trigger
AFTER INSERT OR UPDATE OR DELETE ON shop_reviews
FOR EACH ROW
EXECUTE FUNCTION update_shop_rating();

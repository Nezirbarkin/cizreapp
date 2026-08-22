-- Satıcı Kupon Sistemi
-- Satıcılar kendi mağazaları için kupon oluşturabilir
-- Örnek: 1500TL üzeri alışverişte 100TL indirim

-- Kupon tipi enum
CREATE TYPE coupon_type AS ENUM ('fixed_amount', 'percentage');

-- Satıcı kuponları tablosu
CREATE TABLE IF NOT EXISTS shop_coupons (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  
  -- Kupon bilgileri
  code VARCHAR(50) NOT NULL,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  
  -- İndirim türü ve miktarı
  discount_type coupon_type NOT NULL DEFAULT 'fixed_amount',
  discount_value DECIMAL(10, 2) NOT NULL CHECK (discount_value > 0),
  
  -- Kullanım koşulları
  minimum_order_amount DECIMAL(10, 2) NOT NULL DEFAULT 0 CHECK (minimum_order_amount >= 0),
  maximum_discount_amount DECIMAL(10, 2), -- Sadece percentage için maksimum indirim sınırı
  
  -- Geçerlilik
  is_active BOOLEAN DEFAULT true,
  start_date TIMESTAMPTZ DEFAULT NOW(),
  end_date TIMESTAMPTZ,
  
  -- Kullanım limitleri
  usage_limit INTEGER, -- Toplam kullanım limiti (NULL = sınırsız)
  usage_per_user INTEGER DEFAULT 1, -- Kullanıcı başına kullanım limiti
  usage_count INTEGER DEFAULT 0, -- Toplam kullanım sayısı
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Unique constraint: Her dükkan için kupon kodu benzersiz olmalı
  CONSTRAINT unique_shop_coupon_code UNIQUE (shop_id, code)
);

-- Kupon kullanım geçmişi
CREATE TABLE IF NOT EXISTS coupon_usages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  coupon_id UUID NOT NULL REFERENCES shop_coupons(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  
  discount_amount DECIMAL(10, 2) NOT NULL,
  used_at TIMESTAMPTZ DEFAULT NOW(),
  
  CONSTRAINT unique_coupon_order UNIQUE (coupon_id, order_id)
);

-- İndeksler
CREATE INDEX idx_shop_coupons_shop_id ON shop_coupons(shop_id);
CREATE INDEX idx_shop_coupons_code ON shop_coupons(code);
CREATE INDEX idx_shop_coupons_active ON shop_coupons(is_active) WHERE is_active = true;
CREATE INDEX idx_coupon_usages_coupon_id ON coupon_usages(coupon_id);
CREATE INDEX idx_coupon_usages_user_id ON coupon_usages(user_id);

-- RLS Politikaları
ALTER TABLE shop_coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupon_usages ENABLE ROW LEVEL SECURITY;

-- Herkes aktif kuponları görebilir
DROP POLICY IF EXISTS shop_coupons_select ON shop_coupons;
CREATE POLICY shop_coupons_select ON shop_coupons
  FOR SELECT
  USING (is_active = true OR shop_id IN (
    SELECT id FROM shops WHERE owner_id = auth.uid()
  ));

-- Sadece dükkan sahibi kendi kuponlarını yönetebilir
DROP POLICY IF EXISTS shop_coupons_insert ON shop_coupons;
CREATE POLICY shop_coupons_insert ON shop_coupons
  FOR INSERT
  WITH CHECK (shop_id IN (
    SELECT id FROM shops WHERE owner_id = auth.uid()
  ));

DROP POLICY IF EXISTS shop_coupons_update ON shop_coupons;
CREATE POLICY shop_coupons_update ON shop_coupons
  FOR UPDATE
  USING (shop_id IN (
    SELECT id FROM shops WHERE owner_id = auth.uid()
  ));

DROP POLICY IF EXISTS shop_coupons_delete ON shop_coupons;
CREATE POLICY shop_coupons_delete ON shop_coupons
  FOR DELETE
  USING (shop_id IN (
    SELECT id FROM shops WHERE owner_id = auth.uid()
  ));

-- Coupon usages - herkes kendi kullanımlarını görebilir
DROP POLICY IF EXISTS coupon_usages_select ON coupon_usages;
CREATE POLICY coupon_usages_select ON coupon_usages
  FOR SELECT
  USING (
    user_id = auth.uid() 
    OR coupon_id IN (
      SELECT id FROM shop_coupons 
      WHERE shop_id IN (
        SELECT id FROM shops WHERE owner_id = auth.uid()
      )
    )
  );

-- Sistem coupon usage kaydı ekleyebilir (trigger'dan)
DROP POLICY IF EXISTS coupon_usages_insert ON coupon_usages;
CREATE POLICY coupon_usages_insert ON coupon_usages
  FOR INSERT
  WITH CHECK (true); -- Trigger SECURITY DEFINER ile ekleyecek

-- Kupon doğrulama fonksiyonu
CREATE OR REPLACE FUNCTION validate_and_apply_coupon(
  p_shop_id UUID,
  p_coupon_code VARCHAR,
  p_user_id UUID,
  p_order_amount DECIMAL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coupon RECORD;
  v_user_usage_count INTEGER;
  v_discount_amount DECIMAL;
  v_result JSON;
BEGIN
  -- Kuponu bul ve doğrula
  SELECT * INTO v_coupon
  FROM shop_coupons
  WHERE shop_id = p_shop_id
    AND UPPER(code) = UPPER(p_coupon_code)
    AND is_active = true
    AND (start_date IS NULL OR start_date <= NOW())
    AND (end_date IS NULL OR end_date >= NOW())
    AND (usage_limit IS NULL OR usage_count < usage_limit);
  
  -- Kupon bulunamadı
  IF NOT FOUND THEN
    RETURN json_build_object(
      'valid', false,
      'error', 'Kupon bulunamadı veya geçersiz'
    );
  END IF;
  
  -- Minimum sipariş tutarı kontrolü
  IF p_order_amount < v_coupon.minimum_order_amount THEN
    RETURN json_build_object(
      'valid', false,
      'error', 'Minimum sipariş tutarı: ₺' || v_coupon.minimum_order_amount::TEXT
    );
  END IF;
  
  -- Kullanıcı kullanım limiti kontrolü
  IF v_coupon.usage_per_user IS NOT NULL THEN
    SELECT COUNT(*) INTO v_user_usage_count
    FROM coupon_usages
    WHERE coupon_id = v_coupon.id
      AND user_id = p_user_id;
    
    IF v_user_usage_count >= v_coupon.usage_per_user THEN
      RETURN json_build_object(
        'valid', false,
        'error', 'Bu kuponu kullanım hakkınız dolmuştur'
      );
    END IF;
  END IF;
  
  -- İndirim miktarını hesapla
  IF v_coupon.discount_type = 'fixed_amount' THEN
    v_discount_amount := LEAST(v_coupon.discount_value, p_order_amount);
  ELSE -- percentage
    v_discount_amount := p_order_amount * (v_coupon.discount_value / 100);
    IF v_coupon.maximum_discount_amount IS NOT NULL THEN
      v_discount_amount := LEAST(v_discount_amount, v_coupon.maximum_discount_amount);
    END IF;
  END IF;
  
  -- Sonucu döndür
  RETURN json_build_object(
    'valid', true,
    'coupon_id', v_coupon.id,
    'discount_amount', v_discount_amount,
    'discount_type', v_coupon.discount_type,
    'title', v_coupon.title
  );
END;
$$;

-- Kupon kullanımını kaydet ve sayacı artır
CREATE OR REPLACE FUNCTION record_coupon_usage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Kullanım sayacını artır
  UPDATE shop_coupons
  SET usage_count = usage_count + 1
  WHERE id = NEW.coupon_id;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_record_coupon_usage ON coupon_usages;
CREATE TRIGGER trigger_record_coupon_usage
  AFTER INSERT ON coupon_usages
  FOR EACH ROW
  EXECUTE FUNCTION record_coupon_usage();

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_shop_coupons_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_shop_coupons_updated_at ON shop_coupons;
CREATE TRIGGER trigger_update_shop_coupons_updated_at
  BEFORE UPDATE ON shop_coupons
  FOR EACH ROW
  EXECUTE FUNCTION update_shop_coupons_updated_at();

-- Orders tablosuna kupon alanları ekle
ALTER TABLE orders 
  ADD COLUMN IF NOT EXISTS coupon_id UUID REFERENCES shop_coupons(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS coupon_discount DECIMAL(10, 2) DEFAULT 0;

-- Örnek kuponlar (test için - isteğe bağlı)
COMMENT ON TABLE shop_coupons IS 'Satıcı kupon sistemi - Satıcılar kendi mağazaları için kupon oluşturabilir';
COMMENT ON COLUMN shop_coupons.discount_type IS 'fixed_amount: Sabit tutar indirim, percentage: Yüzdelik indirim';
COMMENT ON COLUMN shop_coupons.minimum_order_amount IS 'Kuponun geçerli olması için minimum sipariş tutarı';
COMMENT ON COLUMN shop_coupons.usage_per_user IS 'Bir kullanıcının bu kuponu kaç kere kullanabileceği';

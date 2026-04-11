-- ============================================================================
-- DÜKKAN DEĞERLENDİRME VE YORUM SİSTEMİ
-- ============================================================================
-- Bu dosya, dükkanlara yorum yazma ve değerlendirme sistemi için gerekli
-- tablo, trigger ve policy'leri içerir.

-- 1. Tablo oluştur
CREATE TABLE IF NOT EXISTS shop_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Bir kullanıcı bir dükkanı sadece bir kez değerlendirebilir
    UNIQUE(shop_id, user_id)
);

-- 2. Index'ler oluştur
CREATE INDEX IF NOT EXISTS idx_shop_reviews_shop_id ON shop_reviews(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_reviews_user_id ON shop_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_shop_reviews_created_at ON shop_reviews(created_at DESC);

-- 3. updated_at trigger'ı
CREATE OR REPLACE FUNCTION update_shop_reviews_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS shop_reviews_updated_at ON shop_reviews;
CREATE TRIGGER shop_reviews_updated_at
    BEFORE UPDATE ON shop_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_shop_reviews_updated_at();

-- 4. Dükkan ortalamasını hesaplayan fonksiyon
CREATE OR REPLACE FUNCTION update_shop_rating()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE shops
    SET 
        rating = COALESCE((
            SELECT AVG(rating)::NUMERIC(3,1)
            FROM shop_reviews
            WHERE shop_id = NEW.shop_id
        ), 0),
        total_reviews = (
            SELECT COUNT(*)
            FROM shop_reviews
            WHERE shop_id = NEW.shop_id
        ),
        updated_at = NOW()
    WHERE id = NEW.shop_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Trigger'ları oluştur (INSERT, UPDATE, DELETE)
DROP TRIGGER IF EXISTS shop_reviews_insert_rating ON shop_reviews;
CREATE TRIGGER shop_reviews_insert_rating
    AFTER INSERT OR UPDATE ON shop_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_shop_rating();

DROP TRIGGER IF EXISTS shop_reviews_delete_rating ON shop_reviews;
CREATE TRIGGER shop_reviews_delete_rating
    AFTER DELETE ON shop_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_shop_rating();

-- 6. Row Level Security (RLS) Policy'leri
ALTER TABLE shop_reviews ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar kendi yorumlarını görebilir
CREATE POLICY "Users can view own reviews" ON shop_reviews
FOR SELECT
TO authenticated
USING ((select auth.uid()) = user_id);

-- Kullanıcılar herkesin yorumlarını görebilir (read-only)
CREATE POLICY "Anyone can view reviews" ON shop_reviews
FOR SELECT
TO authenticated
USING (true);

-- Kullanıcılar yorum yazabilir (INSERT)
CREATE POLICY "Users can insert reviews" ON shop_reviews
FOR INSERT
TO authenticated
WITH CHECK (
    (select auth.uid()) = user_id
    AND rating >= 1 
    AND rating <= 5
);

-- Kullanıcılar kendi yorumlarını güncelleyebilir (UPDATE)
CREATE POLICY "Users can update own reviews" ON shop_reviews
FOR UPDATE
TO authenticated
USING ((select auth.uid()) = user_id)
WITH CHECK (
    (select auth.uid()) = user_id
    AND rating >= 1 
    AND rating <= 5
);

-- Kullanıcılar kendi yorumlarını silebilir (DELETE)
CREATE POLICY "Users can delete own reviews" ON shop_reviews
FOR DELETE
TO authenticated
USING ((select auth.uid()) = user_id);

-- 7. Test verisi (opsiyonel)
INSERT INTO shop_reviews (shop_id, user_id, rating, comment)
SELECT 
    s.id,
    p.id,
    (FLOOR(RANDOM() * 5) + 1)::INTEGER,
    CASE (FLOOR(RANDOM() * 3))
        WHEN 0 THEN 'Harika bir dükkan!'
        WHEN 1 THEN 'Ürünler taze ve lezzetli.'
        ELSE 'Hızlı teslimat, teşekkürler.'
    END
FROM shops s
CROSS JOIN profiles p
WHERE (s.id, p.id) NOT IN (SELECT shop_id, user_id FROM shop_reviews)
LIMIT 20
ON CONFLICT (shop_id, user_id) DO NOTHING;

-- 8. Onay
SELECT 'Shop reviews tablosu başarıyla oluşturuldu!' as status;
SELECT COUNT(*) as total_reviews FROM shop_reviews;

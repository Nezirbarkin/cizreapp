-- =====================================================
-- Ürün Puanlama Sistemi - Minimal Migration (Hatasız)
-- =====================================================

-- 1. product_reviews tablosu
CREATE TABLE IF NOT EXISTS public.product_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    seller_reply TEXT,
    seller_replied_at TIMESTAMPTZ,
    is_approved BOOLEAN DEFAULT true,
    helpful_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. product_review_helpful tablosu
CREATE TABLE IF NOT EXISTS public.product_review_helpful (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id UUID NOT NULL REFERENCES public.product_reviews(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(review_id, user_id)
);

-- 3. Index'ler
CREATE INDEX IF NOT EXISTS idx_product_reviews_product_id ON public.product_reviews(product_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_user_id ON public.product_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_is_approved ON public.product_reviews(is_approved);
CREATE INDEX IF NOT EXISTS idx_product_review_helpful_review_id ON public.product_review_helpful(review_id);

-- 4. products tablosuna rating kolonları ekle
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS rating FLOAT DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS total_reviews INTEGER DEFAULT 0;

-- 5. updated_at otomatik güncelleme
CREATE OR REPLACE FUNCTION update_product_reviews_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS product_reviews_updated_at ON public.product_reviews;
CREATE TRIGGER product_reviews_updated_at
    BEFORE UPDATE ON public.product_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_product_reviews_updated_at();

-- 6. Ürün puanını güncelleme trigger'ı
CREATE OR REPLACE FUNCTION update_product_rating_on_review_change()
RETURNS TRIGGER AS $$
DECLARE
    avg_rating FLOAT;
    total_count INTEGER;
    target_product_id UUID;
BEGIN
    -- Hangi ürünü güncelleyeceğimizi bul
    IF TG_OP = 'DELETE' THEN
        target_product_id := OLD.product_id;
    ELSE
        target_product_id := NEW.product_id;
    END IF;

    -- Ortalama puanı hesapla
    SELECT COALESCE(AVG(rating), 0.0), COUNT(*)
    INTO avg_rating, total_count
    FROM public.product_reviews
    WHERE product_id = target_product_id
      AND is_approved = true;

    -- Ürünü güncelle
    UPDATE public.products
    SET rating = avg_rating,
        total_reviews = total_count
    WHERE id = target_product_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS product_reviews_insert_trigger ON public.product_reviews;
CREATE TRIGGER product_reviews_insert_trigger
    AFTER INSERT ON public.product_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_product_rating_on_review_change();

DROP TRIGGER IF EXISTS product_reviews_update_trigger ON public.product_reviews;
CREATE TRIGGER product_reviews_update_trigger
    AFTER UPDATE ON public.product_reviews
    FOR EACH ROW
    WHEN (OLD.rating IS DISTINCT FROM NEW.rating OR OLD.is_approved IS DISTINCT FROM NEW.is_approved)
    EXECUTE FUNCTION update_product_rating_on_review_change();

DROP TRIGGER IF EXISTS product_reviews_delete_trigger ON public.product_reviews;
CREATE TRIGGER product_reviews_delete_trigger
    AFTER DELETE ON public.product_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_product_rating_on_review_change();

-- 7. RLS Politikaları
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_review_helpful ENABLE ROW LEVEL SECURITY;

-- Herkes onaylı yorumları görebilir
DROP POLICY IF EXISTS "Anyone can view approved product reviews" ON public.product_reviews;
CREATE POLICY "Anyone can view approved product reviews"
    ON public.product_reviews
    FOR SELECT
    USING (is_approved = true);

-- Kullanıcı kendi yorumlarını görebilir
DROP POLICY IF EXISTS "Users can view own product reviews" ON public.product_reviews;
CREATE POLICY "Users can view own product reviews"
    ON public.product_reviews
    FOR SELECT
    USING (auth.uid() = user_id);

-- Kullanıcı yorum ekleyebilir
DROP POLICY IF EXISTS "Users can insert product reviews" ON public.product_reviews;
CREATE POLICY "Users can insert product reviews"
    ON public.product_reviews
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Kullanıcı kendi yorumunu güncelleyebilir
DROP POLICY IF EXISTS "Users can update own product reviews" ON public.product_reviews;
CREATE POLICY "Users can update own product reviews"
    ON public.product_reviews
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Kullanıcı kendi yorumunu silebilir
DROP POLICY IF EXISTS "Users can delete own product reviews" ON public.product_reviews;
CREATE POLICY "Users can delete own product reviews"
    ON public.product_reviews
    FOR DELETE
    USING (auth.uid() = user_id);

-- Kullanıcı faydalı oylayabilir
DROP POLICY IF EXISTS "Users can manage helpful votes" ON public.product_review_helpful;
CREATE POLICY "Users can manage helpful votes"
    ON public.product_review_helpful
    FOR ALL
    USING (auth.uid() = user_id);

-- BAŞARILI! ✅
-- Şimdi Flutter uygulamasında ürün detay ekranında değerlendirme bölümünü görebilirsiniz.

-- =====================================================
-- Ürün Puanlama Sistemi - TAM MIGRATION (TEK DOSYA)
-- =====================================================
-- ⚠️ DİKKAT: Bu dosyayı SIRAYLA ÇALIŞTIRINIZ!
-- Önce STEP1, STEP2, STEP3 dosyalarını çalıştırın.

-- =====================================================
-- ADIM 1: product_reviews tablosu
-- =====================================================
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

-- =====================================================
-- ADIM 2: product_review_helpful tablosu
-- =====================================================
CREATE TABLE IF NOT EXISTS public.product_review_helpful (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id UUID NOT NULL REFERENCES public.product_reviews(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(review_id, user_id)
);

-- =====================================================
-- ADIM 3: products tablosuna rating kolonları
-- =====================================================
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS rating FLOAT DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS total_reviews INTEGER DEFAULT 0;

-- =====================================================
-- ADIM 4: Index'ler
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_product_reviews_product_id ON public.product_reviews(product_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_user_id ON public.product_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_is_approved ON public.product_reviews(is_approved);
CREATE INDEX IF NOT EXISTS idx_product_review_helpful_review_id ON public.product_review_helpful(review_id);

-- =====================================================
-- ADIM 5: updated_at otomatik güncelleme
-- =====================================================
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

-- =====================================================
-- ADIM 6: Ürün puanını güncelleme trigger'ı
-- =====================================================
CREATE OR REPLACE FUNCTION update_product_rating_on_review_change()
RETURNS TRIGGER AS $$
DECLARE
    avg_rating FLOAT;
    total_count INTEGER;
    target_product_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_product_id := OLD.product_id;
    ELSE
        target_product_id := NEW.product_id;
    END IF;

    SELECT COALESCE(AVG(rating), 0.0), COUNT(*)
    INTO avg_rating, total_count
    FROM public.product_reviews
    WHERE product_id = target_product_id
      AND is_approved = true;

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

-- Trigger'ları oluştur
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

-- =====================================================
-- ADIM 7: RLS (Row Level Security) Politikaları
-- =====================================================
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

-- Kullanıcı yorum ekleyebilir (ürünü satın almış olmalı)
-- Not: hasPurchasedProduct kontrolü Flutter tarafında yapılıyor
DROP POLICY IF EXISTS "Users can insert product reviews" ON public.product_reviews;
CREATE POLICY "Users can insert product reviews"
    ON public.product_reviews
    FOR INSERT
    WITH CHECK (
        auth.uid() = user_id
        AND EXISTS (
            SELECT 1
            FROM public.order_items oi
            JOIN public.orders o ON o.id = oi.order_id
            WHERE o.user_id = auth.uid()
              AND o.status = 'delivered'
              AND oi.product_id = product_id
            LIMIT 1
        )
    );

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

-- Faydalı oylama politikası
DROP POLICY IF EXISTS "Users can manage helpful votes" ON public.product_review_helpful;
CREATE POLICY "Users can manage helpful votes"
    ON public.product_review_helpful
    FOR ALL
    USING (auth.uid() = user_id);

-- =====================================================
-- ADIM 8: Faydalı oy sayısını güncelleme (opsiyonel)
-- =====================================================
CREATE OR REPLACE FUNCTION update_helpful_count_on_vote()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.product_reviews
        SET helpful_count = helpful_count + 1
        WHERE id = NEW.review_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.product_reviews
        SET helpful_count = GREATEST(helpful_count - 1, 0)
        WHERE id = OLD.review_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS product_review_helpful_insert_trigger ON public.product_review_helpful;
CREATE TRIGGER product_review_helpful_insert_trigger
    AFTER INSERT ON public.product_review_helpful
    FOR EACH ROW
    EXECUTE FUNCTION update_helpful_count_on_vote();

DROP TRIGGER IF EXISTS product_review_helpful_delete_trigger ON public.product_review_helpful;
CREATE TRIGGER product_review_helpful_delete_trigger
    AFTER DELETE ON public.product_review_helpful
    FOR EACH ROW
    EXECUTE FUNCTION update_helpful_count_on_vote();

-- =====================================================
-- TAMAMLANDI ✅
-- =====================================================
COMMENT ON TABLE public.product_reviews IS 'Ürün puanlama ve yorum tablosu';
COMMENT ON TABLE public.product_review_helpful IS 'Ürün yorumları faydalı oyları tablosu';

-- Şimdi bu migration'ı Supabase Dashboard'da çalıştırabilirsiniz!
-- Önceki STEP1, STEP2, STEP3 ve PRODUCT_REVIEWS_MINIMAL.SQL dosyalarını silin.
-- Sonra bu PRODUCT_REVIEWS_COMPLETE.SQL dosyasını çalıştırın.

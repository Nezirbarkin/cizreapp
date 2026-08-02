-- =====================================================
-- ÜRÜN PUANLAMA SİSTEMİ - TEMİZ KURULUM
-- Bu dosyayı TEK SEFERDE çalıştırın
-- Eski tabloları silip sıfırdan oluşturur
-- =====================================================

-- 1) Eski tabloları ve trigger'ları temizle
DROP TRIGGER IF EXISTS product_reviews_updated_at ON public.product_reviews;
DROP TRIGGER IF EXISTS product_reviews_insert_trigger ON public.product_reviews;
DROP TRIGGER IF EXISTS product_reviews_update_trigger ON public.product_reviews;
DROP TRIGGER IF EXISTS product_reviews_delete_trigger ON public.product_reviews;
DROP TRIGGER IF EXISTS product_review_helpful_insert_trigger ON public.product_review_helpful;
DROP TRIGGER IF EXISTS product_review_helpful_delete_trigger ON public.product_review_helpful;

DROP TABLE IF EXISTS public.product_review_helpful CASCADE;
DROP TABLE IF EXISTS public.product_reviews CASCADE;

DROP FUNCTION IF EXISTS update_product_reviews_updated_at() CASCADE;
DROP FUNCTION IF EXISTS update_product_rating_on_review_change() CASCADE;
DROP FUNCTION IF EXISTS update_helpful_count_on_vote() CASCADE;

-- 2) product_reviews tablosunu oluştur
CREATE TABLE public.product_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    seller_reply TEXT,
    seller_replied_at TIMESTAMPTZ,
    is_approved BOOLEAN DEFAULT true,
    helpful_count INTEGER DEFAULT 0,
    order_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3) product_review_helpful tablosunu oluştur
CREATE TABLE public.product_review_helpful (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id UUID NOT NULL REFERENCES public.product_reviews(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(review_id, user_id)
);

-- 4) products tablosuna rating ve total_reviews kolonları ekle
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS rating DOUBLE PRECISION DEFAULT 0.0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS total_reviews INTEGER DEFAULT 0;

-- 5) Index'ler
CREATE INDEX IF NOT EXISTS idx_product_reviews_product_id ON public.product_reviews(product_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_user_id ON public.product_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_is_approved ON public.product_reviews(is_approved);
CREATE INDEX IF NOT EXISTS idx_product_review_helpful_review_id ON public.product_review_helpful(review_id);

-- 6) updated_at otomatik güncelleme fonksiyonu
CREATE OR REPLACE FUNCTION update_product_reviews_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER product_reviews_updated_at
    BEFORE UPDATE ON public.product_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_product_reviews_updated_at();

-- 7) Ürün puanını otomatik güncelleme trigger'ı
CREATE OR REPLACE FUNCTION update_product_rating_on_review_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
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
$$;

CREATE TRIGGER product_reviews_insert_trigger
    AFTER INSERT ON public.product_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_product_rating_on_review_change();

CREATE TRIGGER product_reviews_update_trigger
    AFTER UPDATE ON public.product_reviews
    FOR EACH ROW
    WHEN (OLD.rating IS DISTINCT FROM NEW.rating OR OLD.is_approved IS DISTINCT FROM NEW.is_approved)
    EXECUTE FUNCTION update_product_rating_on_review_change();

CREATE TRIGGER product_reviews_delete_trigger
    AFTER DELETE ON public.product_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_product_rating_on_review_change();

-- 8) Faydalı oy sayısını güncelleme trigger'ı
CREATE OR REPLACE FUNCTION update_helpful_count_on_vote()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
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
$$;

CREATE TRIGGER product_review_helpful_insert_trigger
    AFTER INSERT ON public.product_review_helpful
    FOR EACH ROW
    EXECUTE FUNCTION update_helpful_count_on_vote();

CREATE TRIGGER product_review_helpful_delete_trigger
    AFTER DELETE ON public.product_review_helpful
    FOR EACH ROW
    EXECUTE FUNCTION update_helpful_count_on_vote();

-- 9) RLS (Row Level Security) etkinleştir
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_review_helpful ENABLE ROW LEVEL SECURITY;

-- product_reviews RLS politikaları
CREATE POLICY "Herkes onaylı yorumları görebilir"
    ON public.product_reviews FOR SELECT
    USING (is_approved = true);

CREATE POLICY "Kullanıcılar kendi yorumlarını görebilir"
    ON public.product_reviews FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Kullanıcılar yorum ekleyebilir"
    ON public.product_reviews FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Kullanıcılar kendi yorumlarını güncelleyebilir"
    ON public.product_reviews FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Kullanıcılar kendi yorumlarını silebilir"
    ON public.product_reviews FOR DELETE
    USING (auth.uid() = user_id);

-- product_review_helpful RLS politikaları
CREATE POLICY "Herkes faydalı oyları görebilir"
    ON public.product_review_helpful FOR SELECT
    USING (true);

CREATE POLICY "Kullanıcılar faydalı oyu verebilir"
    ON public.product_review_helpful FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Kullanıcılar kendi faydalı oylarını silebilir"
    ON public.product_review_helpful FOR DELETE
    USING (auth.uid() = user_id);

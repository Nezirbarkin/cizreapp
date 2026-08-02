-- =====================================================
-- ADIM 4: Index'ler ve Trigger'lar
-- =====================================================

-- Index'ler
CREATE INDEX IF NOT EXISTS idx_product_reviews_product_id ON public.product_reviews(product_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_user_id ON public.product_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_is_approved ON public.product_reviews(is_approved);
CREATE INDEX IF NOT EXISTS idx_product_review_helpful_review_id ON public.product_review_helpful(review_id);

-- updated_at otomatik güncelleme
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

-- Ürün puanını güncelleme trigger'ı
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

-- Faydalı oy sayısını güncelleme
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

-- =====================================================
-- Ürün Puanlama Sistemi - Supabase Migration
-- =====================================================

-- 1. product_reviews tablosunu oluştur
CREATE TABLE IF NOT EXISTS public.product_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    seller_reply TEXT,
    seller_replied_at TIMESTAMPTZ,
    is_approved BOOLEAN DEFAULT true,
    helpful_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. product_review_helpful tablosunu oluştur (faydalı oyları için)
CREATE TABLE IF NOT EXISTS public.product_review_helpful (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id UUID NOT NULL REFERENCES public.product_reviews(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(review_id, user_id)
);

-- 3. Index'leri oluştur
CREATE INDEX IF NOT EXISTS idx_product_reviews_product_id ON public.product_reviews(product_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_user_id ON public.product_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_order_id ON public.product_reviews(order_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_is_approved ON public.product_reviews(is_approved);
CREATE INDEX IF NOT EXISTS idx_product_review_helpful_review_id ON public.product_review_helpful(review_id);
CREATE INDEX IF NOT EXISTS idx_product_review_helpful_user_id ON public.product_review_helpful(user_id);

-- 4. Ürünlerin rating ve total_reviews alanlarını ekle (products tablosu)
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS rating FLOAT DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS total_reviews INTEGER DEFAULT 0;

-- 5. updated_at otomatik güncelleme fonksiyonu
CREATE OR REPLACE FUNCTION update_product_reviews_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER product_reviews_updated_at
    BEFORE UPDATE ON public.product_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_product_reviews_updated_at();

-- 6. Yorum eklendiğinde/değiştiğinde/silindiğinde ürün puanını otomatik güncelle
CREATE OR REPLACE FUNCTION update_product_rating_on_review_change()
RETURNS TRIGGER AS $$
DECLARE
    avg_rating FLOAT;
    total_count INTEGER;
BEGIN
    -- Ortalama puanı hesapla
    SELECT COALESCE(AVG(rating), 0.0), COUNT(*)
    INTO avg_rating, total_count
    FROM public.product_reviews
    WHERE product_id = COALESCE(NEW.product_id, OLD.product_id)
      AND is_approved = true;

    -- Ürünün puanını güncelle
    UPDATE public.products
    SET rating = avg_rating,
        total_reviews = total_count
    WHERE id = COALESCE(NEW.product_id, OLD.product_id);

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger'ları oluştur
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

-- 7. Faydalı sayısını güncelleme fonksiyonu
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

CREATE TRIGGER product_review_helpful_insert_trigger
    AFTER INSERT ON public.product_review_helpful
    FOR EACH ROW
    EXECUTE FUNCTION update_helpful_count_on_vote();

CREATE TRIGGER product_review_helpful_delete_trigger
    AFTER DELETE ON public.product_review_helpful
    FOR EACH ROW
    EXECUTE FUNCTION update_helpful_count_on_vote();

-- 8. Kullanıcının bir ürünü daha önce yorumlayıp yorumlamadığını kontrol eden fonksiyon
CREATE OR REPLACE FUNCTION can_review_product(p_user_id UUID, p_product_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM public.order_items oi
        JOIN public.orders o ON o.id = oi.order_id
        WHERE o.user_id = p_user_id
          AND oi.product_id = p_product_id
          AND o.status = 'delivered'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. RLS (Row Level Security) politikaları

-- product_reviews için RLS'i aktif et
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;

-- Herkes onaylı yorumları görebilir
CREATE POLICY "Anyone can view approved product reviews"
    ON public.product_reviews
    FOR SELECT
    USING (is_approved = true);

-- Kullanıcı kendi yorumlarını görebilir
CREATE POLICY "Users can view own product reviews"
    ON public.product_reviews
    FOR SELECT
    USING (auth.uid() = user_id);

-- Kullanıcı yorum ekleyebilir (eğer ürünü satın almışsa)
CREATE POLICY "Users can insert product reviews if purchased"
    ON public.product_reviews
    FOR INSERT
    WITH CHECK (
        auth.uid() = user_id
        AND can_review_product(auth.uid(), product_id)
    );

-- Kullanıcı kendi yorumunu güncelleyebilir
CREATE POLICY "Users can update own product reviews"
    ON public.product_reviews
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Kullanıcı kendi yorumunu silebilir
CREATE POLICY "Users can delete own product reviews"
    ON public.product_reviews
    FOR DELETE
    USING (auth.uid() = user_id);

-- Satıcı (shop owner) kendi ürünlerine gelen yorumları görebilir
CREATE POLICY "Shop owners can view reviews for their products"
    ON public.product_reviews
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.products p
            JOIN public.shops s ON s.id = p.shop_id
            WHERE p.id = product_reviews.product_id
              AND s.owner_id = auth.uid()
        )
    );

-- Satıcı yorumlara cevap verebilir
CREATE POLICY "Shop owners can reply to reviews"
    ON public.product_reviews
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1
            FROM public.products p
            JOIN public.shops s ON s.id = p.shop_id
            WHERE p.id = product_reviews.product_id
              AND s.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.products p
            JOIN public.shops s ON s.id = p.shop_id
            WHERE p.id = product_reviews.product_id
              AND s.owner_id = auth.uid()
        )
    );

-- Admin tüm yorumları görebilir ve yönetebilir
CREATE POLICY "Admins can view all product reviews"
    ON public.product_reviews
    FOR ALL
    USING (
        EXISTS (
            SELECT 1
            FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- product_review_helpful için RLS'i aktif et
ALTER TABLE public.product_review_helpful ENABLE ROW LEVEL SECURITY;

-- Kullanıcı kendi oy kaydını görebilir
CREATE POLICY "Users can view own helpful votes"
    ON public.product_review_helpful
    FOR SELECT
    USING (auth.uid() = user_id);

-- Kullanıcı oy ekleyebilir
CREATE POLICY "Users can insert helpful votes"
    ON public.product_review_helpful
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Kullanıcı kendi oyunu silebilir
CREATE POLICY "Users can delete own helpful votes"
    ON public.product_review_helpful
    FOR DELETE
    USING (auth.uid() = user_id);

-- 10. Mevcut veriler için puan hesaplama (opsiyonel - varsa)
DO $$
DECLARE
    product_record RECORD;
    avg_rating FLOAT;
    total_count INTEGER;
BEGIN
    FOR product_record IN 
        SELECT DISTINCT product_id FROM public.product_reviews
    LOOP
        SELECT COALESCE(AVG(rating), 0.0), COUNT(*)
        INTO avg_rating, total_count
        FROM public.product_reviews
        WHERE product_id = product_record.product_id
          AND is_approved = true;

        UPDATE public.products
        SET rating = avg_rating,
            total_reviews = total_count
        WHERE id = product_record.product_id;
    END LOOP;
END $$;

-- 11. Yorumlar için comments
COMMENT ON TABLE public.product_reviews IS 'Ürün puanlama ve yorum tablosu';
COMMENT ON COLUMN public.product_reviews.product_id IS 'Ürün ID (referans: products)';
COMMENT ON COLUMN public.product_reviews.user_id IS 'Kullanıcı ID (referans: users)';
COMMENT ON COLUMN public.product_reviews.rating IS 'Puan (1-5 arası)';
COMMENT ON COLUMN public.product_reviews.comment IS 'Yorum metni';
COMMENT ON COLUMN public.product_reviews.seller_reply IS 'Satıcının cevabı';
COMMENT ON COLUMN public.product_reviews.is_approved IS 'Yorum onaylı mı?';
COMMENT ON COLUMN public.product_reviews.helpful_count IS 'Kaç kişi bunu faydalı buldu?';

COMMENT ON TABLE public.product_review_helpful IS 'Ürün yorumları faydalı oyları tablosu';
COMMENT ON COLUMN public.product_review_helpful.review_id IS 'Yorum ID';
COMMENT ON COLUMN public.product_review_helpful.user_id IS 'Oy veren kullanıcı ID';

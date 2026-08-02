-- =====================================================
-- ADIM 3: products tablosuna rating kolonları ekle
-- =====================================================
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS rating FLOAT DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS total_reviews INTEGER DEFAULT 0;

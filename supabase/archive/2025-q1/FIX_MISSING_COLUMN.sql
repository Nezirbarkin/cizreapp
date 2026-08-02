-- =====================================================
-- Eksik is_approved kolonunu ekle
-- =====================================================

-- is_approved kolonu eksikse ekle
ALTER TABLE public.product_reviews 
ADD COLUMN IF NOT EXISTS is_approved BOOLEAN DEFAULT true;

-- helpful_count kolonu eksikse ekle (güvenlik için)
ALTER TABLE public.product_reviews 
ADD COLUMN IF NOT EXISTS helpful_count INTEGER DEFAULT 0;

-- seller_reply kolonları eksikse ekle (güvenlik için)
ALTER TABLE public.product_reviews 
ADD COLUMN IF NOT EXISTS seller_reply TEXT;

ALTER TABLE public.product_reviews 
ADD COLUMN IF NOT EXISTS seller_replied_at TIMESTAMPTZ;

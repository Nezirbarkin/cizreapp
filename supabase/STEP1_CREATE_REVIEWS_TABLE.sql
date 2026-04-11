-- =====================================================
-- Ürün Puanlama Sistemi - Adım Adım Migration
-- HER ADIMI TEK TEK ÇALIŞTIRIN
-- =====================================================

-- =====================================================
-- ADIM 1: product_reviews tablosu oluştur
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

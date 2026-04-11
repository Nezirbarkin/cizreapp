-- =====================================================
-- SHOP ANALYTICS TABLES
-- =====================================================
-- Mağaza ziyaretleri, ürün tıklamaları ve satış istatistikleri

-- =====================================================
-- 1. Shop Views Table (Mağaza Ziyaretleri)
-- =====================================================
CREATE TABLE IF NOT EXISTS public.shop_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    viewed_at TIMESTAMPTZ DEFAULT NOW(),
    session_id TEXT, -- Anonim kullanıcılar için
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shop_views_shop_id ON public.shop_views(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_views_viewed_at ON public.shop_views(viewed_at);
CREATE INDEX IF NOT EXISTS idx_shop_views_user_id ON public.shop_views(user_id) WHERE user_id IS NOT NULL;

-- =====================================================
-- 2. Product Views Table (Ürün Görüntülemeleri)
-- =====================================================
CREATE TABLE IF NOT EXISTS public.product_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    viewed_at TIMESTAMPTZ DEFAULT NOW(),
    session_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_product_views_product_id ON public.product_views(product_id);
CREATE INDEX IF NOT EXISTS idx_product_views_shop_id ON public.product_views(shop_id);
CREATE INDEX IF NOT EXISTS idx_product_views_viewed_at ON public.product_views(viewed_at);

-- =====================================================
-- 3. RLS Policies
-- =====================================================

-- Shop Views Policies
ALTER TABLE public.shop_views ENABLE ROW LEVEL SECURITY;

-- Herkes görüntüleme kaydedebilir
CREATE POLICY shop_views_insert_policy ON public.shop_views
    FOR INSERT
    TO authenticated, anon
    WITH CHECK (true);

-- Sadece mağaza sahibi kendi görüntülemelerini görebilir
CREATE POLICY shop_views_select_policy ON public.shop_views
    FOR SELECT
    TO authenticated
    USING (
        shop_id IN (
            SELECT id FROM public.shops WHERE owner_id = (SELECT auth.uid())
        )
        OR EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE id = (SELECT auth.uid()) AND role = 'admin'
        )
    );

-- Product Views Policies
ALTER TABLE public.product_views ENABLE ROW LEVEL SECURITY;

-- Herkes görüntüleme kaydedebilir
CREATE POLICY product_views_insert_policy ON public.product_views
    FOR INSERT
    TO authenticated, anon
    WITH CHECK (true);

-- Sadece mağaza sahibi kendi ürün görüntülemelerini görebilir
CREATE POLICY product_views_select_policy ON public.product_views
    FOR SELECT
    TO authenticated
    USING (
        shop_id IN (
            SELECT id FROM public.shops WHERE owner_id = (SELECT auth.uid())
        )
        OR EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE id = (SELECT auth.uid()) AND role = 'admin'
        )
    );

-- =====================================================
-- 4. Analytics Functions
-- =====================================================

-- Mağaza için toplam görüntüleme sayısı
CREATE OR REPLACE FUNCTION get_shop_total_views(p_shop_id UUID)
RETURNS BIGINT
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COUNT(*) FROM public.shop_views WHERE shop_id = p_shop_id;
$$;

-- Mağaza için bugünün görüntüleme sayısı
CREATE OR REPLACE FUNCTION get_shop_today_views(p_shop_id UUID)
RETURNS BIGINT
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COUNT(*) FROM public.shop_views 
    WHERE shop_id = p_shop_id 
    AND viewed_at >= CURRENT_DATE;
$$;

-- En çok görüntülenen ürünler
CREATE OR REPLACE FUNCTION get_top_viewed_products(p_shop_id UUID, p_limit INT DEFAULT 10)
RETURNS TABLE (
    product_id UUID,
    product_name TEXT,
    view_count BIGINT
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT 
        pv.product_id,
        p.name as product_name,
        COUNT(*) as view_count
    FROM public.product_views pv
    JOIN public.products p ON p.id = pv.product_id
    WHERE pv.shop_id = p_shop_id
    GROUP BY pv.product_id, p.name
    ORDER BY view_count DESC
    LIMIT p_limit;
$$;

-- En çok sipariş veren kullanıcılar
CREATE OR REPLACE FUNCTION get_top_customers(p_shop_id UUID, p_limit INT DEFAULT 10)
RETURNS TABLE (
    user_id UUID,
    full_name TEXT,
    order_count BIGINT,
    total_spent NUMERIC
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        o.user_id,
        prof.full_name,
        COUNT(DISTINCT o.id) as order_count,
        COALESCE(SUM(o.subtotal), 0) as total_spent
    FROM public.orders o
    JOIN public.profiles prof ON prof.id = o.user_id
    WHERE o.shop_id = p_shop_id
    AND o.status != 'cancelled'
    GROUP BY o.user_id, prof.full_name
    ORDER BY order_count DESC, total_spent DESC
    LIMIT p_limit;
$$;

COMMENT ON TABLE public.shop_views IS 'Mağaza ziyaret kayıtları';
COMMENT ON TABLE public.product_views IS 'Ürün görüntüleme kayıtları';
COMMENT ON FUNCTION get_shop_total_views IS 'Mağazanın toplam görüntülenme sayısı';
COMMENT ON FUNCTION get_top_viewed_products IS 'En çok görüntülenen ürünler';
COMMENT ON FUNCTION get_top_customers IS 'En çok sipariş veren müşteriler';

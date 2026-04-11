-- ==============================================================================
-- FIX: Mağaza Ziyaret Sayısı Sorunları
-- ==============================================================================
-- 1. shop_views tablosunun var olup olmadığını kontrol et
-- 2. RPC fonksiyonlarının var olup olmadığını kontrol et
-- 3. Yoksa oluştur
-- ==============================================================================

-- 1. shop_views tablosu var mı kontrol et
SELECT 
    tablename,
    schemaname
FROM pg_tables 
WHERE tablename = 'shop_views';

-- 2. RPC fonksiyonları var mı kontrol et
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN ('get_shop_total_views', 'get_shop_today_views');

-- 3. Eğer shop_views tablosu yoksa oluştur
CREATE TABLE IF NOT EXISTS public.shop_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    session_id TEXT,
    viewed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_shop_views_shop_id ON public.shop_views(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_views_user_id ON public.shop_views(user_id);
CREATE INDEX IF NOT EXISTS idx_shop_views_viewed_at ON public.shop_views(viewed_at);

-- RLS politikaları
ALTER TABLE public.shop_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "shop_views_select_all" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_insert_authenticated" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_select_owner_or_admin" ON public.shop_views;

-- Tek bir unified SELECT policy
CREATE POLICY "shop_views_select_all"
    ON public.shop_views
    FOR SELECT
    TO public, authenticated
    USING (true);

-- INSERT policy - sadece authenticated kullanıcılar (initplan uyarısını önlemek için SELECT kullan)
CREATE POLICY "shop_views_insert_authenticated"
    ON public.shop_views
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()) OR user_id IS NULL);

-- 4. RPC fonksiyonları oluştur

-- Toplam görüntüleme
CREATE OR REPLACE FUNCTION public.get_shop_total_views(p_shop_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN (SELECT COUNT(*)::INTEGER FROM public.shop_views WHERE shop_id = p_shop_id);
END;
$$;

-- Bugünkü görüntüleme
CREATE OR REPLACE FUNCTION public.get_shop_today_views(p_shop_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_today_start TIMESTAMPTZ;
BEGIN
    v_today_start := DATE_TRUNC('day', NOW());
    RETURN (
        SELECT COUNT(*)::INTEGER 
        FROM public.shop_views 
        WHERE shop_id = p_shop_id 
        AND viewed_at >= v_today_start
    );
END;
$$;

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '✅ shop_views tablosu ve RPC fonksiyonları hazır';
    RAISE NOTICE '✅ get_shop_total_views() fonksiyonu eklendi';
    RAISE NOTICE '✅ get_shop_today_views() fonksiyonu eklendi';
END $$;

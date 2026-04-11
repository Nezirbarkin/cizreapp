-- =====================================================
-- MAĞAZA ZİYARETLERİ RLS SORUNU ÇÖZÜMÜ
-- shop_views ve product_views tablolarının RLS politikalarını düzelt
-- =====================================================

-- SORUN: SELECT politikası mağaza sahibinin kendi verilerini okumasını engelliyor
-- ÇÖZÜM: RPC fonksiyonları SECURITY DEFINER ile çalışsın ve tüm verilere erişebilsin

-- =====================================================
-- 1) shop_views SELECT politikasını düzelt
-- =====================================================

-- Eski politikaları sil
DROP POLICY IF EXISTS "shop_views_select_policy" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_select_public" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_select" ON public.shop_views;

-- Yeni politika: Authenticated kullanıcılar kendi mağazalarının verilerini görebilir veya admin
CREATE POLICY "shop_views_select_owner_or_admin"
ON public.shop_views
FOR SELECT
TO authenticated
USING (
    -- Mağaza sahibi kendi verilerini görebilir
    shop_id IN (
        SELECT id FROM public.shops 
        WHERE owner_id = auth.uid()
    )
    OR
    -- Admin tüm verileri görebilir
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role = 'admin'
    )
);

-- =====================================================
-- 2) product_views SELECT politikasını düzelt
-- =====================================================

-- Eski politikaları sil
DROP POLICY IF EXISTS "product_views_select_policy" ON public.product_views;
DROP POLICY IF EXISTS "product_views_select_public" ON public.product_views;
DROP POLICY IF EXISTS "product_views_select" ON public.product_views;

-- Yeni politika: Authenticated kullanıcılar kendi mağazalarının ürün verilerini görebilir veya admin
CREATE POLICY "product_views_select_owner_or_admin"
ON public.product_views
FOR SELECT
TO authenticated
USING (
    -- Mağaza sahibi kendi ürünlerinin verilerini görebilir
    shop_id IN (
        SELECT id FROM public.shops 
        WHERE owner_id = auth.uid()
    )
    OR
    -- Admin tüm verileri görebilir
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role = 'admin'
    )
);

-- =====================================================
-- 3) INSERT politikaları aynen kalsın (herkes ekleyebilir)
-- =====================================================
-- INSERT politikaları değiştirilmedi, herkes (authenticated + anon) 
-- görüntüleme kaydedebilir

-- =====================================================
-- 4) RPC fonksiyonları SECURITY DEFINER ile çalışıyor
-- =====================================================
-- get_shop_total_views, get_shop_today_views, get_top_viewed_products, get_top_customers
-- Bu fonksiyonlar SECURITY DEFINER ile çalışıyor, bu nedenle RLS bypass ediliyor
-- Ancak SELECT politikası olmalı ki normal sorgular da çalışsın

-- =====================================================
-- TEST
-- =====================================================
-- Satıcı panelinde raporlar ekranını açın
-- Mağaza ziyareti sayısı artık 0 yerine gerçek değeri göstermeli

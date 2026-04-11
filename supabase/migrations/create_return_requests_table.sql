-- =============================================
-- İADE TALEPLERİ TABLOSU OLUŞTURMA (OPTİMİZE)
-- Bu dosyayı Supabase SQL Editor'de çalıştırın
-- =============================================

-- Mevcut politikaları sil (eğer varsa)
DROP POLICY IF EXISTS "Users can view own return requests" ON public.return_requests;
DROP POLICY IF EXISTS "Users can create return requests" ON public.return_requests;
DROP POLICY IF EXISTS "Sellers can view shop return requests" ON public.return_requests;
DROP POLICY IF EXISTS "Sellers can update shop return requests" ON public.return_requests;
DROP POLICY IF EXISTS "Admin can view all return requests" ON public.return_requests;
DROP POLICY IF EXISTS "Admin can update all return requests" ON public.return_requests;

-- Tabloyu sil (eğer varsa)
DROP TABLE IF EXISTS public.return_requests;

-- return_requests tablosu oluştur
CREATE TABLE public.return_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'completed')),
    admin_response TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- İndeksler
CREATE INDEX idx_return_requests_order_id ON public.return_requests(order_id);
CREATE INDEX idx_return_requests_user_id ON public.return_requests(user_id);
CREATE INDEX idx_return_requests_shop_id ON public.return_requests(shop_id);
CREATE INDEX idx_return_requests_status ON public.return_requests(status);

-- Her sipariş için tek iade talebi olabilir
CREATE UNIQUE INDEX idx_return_requests_order_unique ON public.return_requests(order_id);

-- RLS Etkinleştir
ALTER TABLE public.return_requests ENABLE ROW LEVEL SECURITY;

-- =============================================
-- OPTİMİZE EDİLMİŞ RLS POLİTİKALARI
-- (select auth.uid()) kullanılarak performans artırıldı
-- =============================================

-- Tüm roller için SELECT politikası (birleştirilmiş)
CREATE POLICY "Allow select based on role"
    ON public.return_requests
    FOR SELECT
    TO authenticated
    USING (
        -- Kullanıcı kendi taleplerini görebilir
        user_id = (SELECT auth.uid())
        OR
        -- Satıcı dükkanının taleplerini görebilir
        shop_id IN (
            SELECT id FROM public.shops WHERE owner_id = (SELECT auth.uid())
        )
        OR
        -- Admin tüm talepleri görebilir
        (SELECT auth.uid()) IN (
            SELECT id FROM public.profiles WHERE role = 'admin'
        )
    );

-- Kullanıcılar iade talebi oluşturabilir
CREATE POLICY "Users can create return requests"
    ON public.return_requests
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));

-- Satıcılar ve Admin güncelleme yapabilir (birleştirilmiş)
CREATE POLICY "Allow update based on role"
    ON public.return_requests
    FOR UPDATE
    TO authenticated
    USING (
        -- Satıcı dükkanının taleplerini güncelleyebilir
        shop_id IN (
            SELECT id FROM public.shops WHERE owner_id = (SELECT auth.uid())
        )
        OR
        -- Admin tüm talepleri güncelleyebilir
        (SELECT auth.uid()) IN (
            SELECT id FROM public.profiles WHERE role = 'admin'
        )
    );

-- =============================================
-- YORUM
-- =============================================
-- Bu tablo iade taleplerini yönetir.
-- - Müşteriler: Kendi taleplerini görebilir ve oluşturabilir
-- - Satıcılar: Dükkanlarının taleplerini görebilir ve güncelleyebilir
-- - Admin: Tüm talepleri görebilir ve güncelleyebilir
-- 
-- Performans optimizasyonu: (SELECT auth.uid()) kullanıldı
-- Multiple permissive policy yerine tek birleştirilmiş policy

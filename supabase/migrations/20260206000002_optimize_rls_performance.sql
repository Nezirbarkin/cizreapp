-- ============================================================================
-- RLS POLİTİKALARI PERFORMANS OPTİMİZASYONU
-- ============================================================================
-- auth.uid() yerine (select auth.uid()) kullanarak performansı artır
-- Multiple permissive policies'i tek policy'de birleştir

-- ============================================================================
-- 1. EMAIL_SETTINGS TABLOSU - auth_rls_initplan DÜZELT
-- ============================================================================

-- Mevcut politikaları kaldır
DROP POLICY IF EXISTS "Admins can view email settings" ON public.email_settings;
DROP POLICY IF EXISTS "Admins can update email settings" ON public.email_settings;
DROP POLICY IF EXISTS "Admins can insert email settings" ON public.email_settings;

-- Yeni optimize edilmiş politikalar
CREATE POLICY "Admins can view email settings"
ON public.email_settings FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = (SELECT auth.uid()) 
        AND role = 'admin'
    )
);

CREATE POLICY "Admins can update email settings"
ON public.email_settings FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = (SELECT auth.uid()) 
        AND role = 'admin'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = (SELECT auth.uid()) 
        AND role = 'admin'
    )
);

CREATE POLICY "Admins can insert email settings"
ON public.email_settings FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = (SELECT auth.uid()) 
        AND role = 'admin'
    )
);

-- ============================================================================
-- 2. COURIER_REQUESTS TABLOSU - auth_rls_initplan ve multiple_permissive DÜZELT
-- ============================================================================

-- Mevcut politikaları kaldır
DROP POLICY IF EXISTS "seller_view_own_courier_requests" ON public.courier_requests;
DROP POLICY IF EXISTS "seller_create_courier_request" ON public.courier_requests;
DROP POLICY IF EXISTS "admin_manage_courier_requests" ON public.courier_requests;

-- Tek bir SELECT politikası (OR ile birleştir)
CREATE POLICY "courier_requests_select_policy"
ON public.courier_requests FOR SELECT
TO authenticated
USING (
    -- Satıcı kendi taleplerini görebilir
    EXISTS (
        SELECT 1 FROM shops s
        WHERE s.id = courier_requests.shop_id
        AND s.owner_id = (SELECT auth.uid())
    )
    OR
    -- Admin hepsini görebilir
    EXISTS (
        SELECT 1 FROM profiles
        WHERE id = (SELECT auth.uid())
        AND role = 'admin'
    )
);

-- Tek bir INSERT politikası (OR ile birleştir)
CREATE POLICY "courier_requests_insert_policy"
ON public.courier_requests FOR INSERT
TO authenticated
WITH CHECK (
    -- Satıcı kendi mağazası için talep oluşturabilir
    EXISTS (
        SELECT 1 FROM shops s
        WHERE s.id = courier_requests.shop_id
        AND s.owner_id = (SELECT auth.uid())
    )
    OR
    -- Admin herkes için oluşturabilir
    EXISTS (
        SELECT 1 FROM profiles
        WHERE id = (SELECT auth.uid())
        AND role = 'admin'
    )
);

-- UPDATE politikası - Admin için
CREATE POLICY "courier_requests_update_policy"
ON public.courier_requests FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles
        WHERE id = (SELECT auth.uid())
        AND role = 'admin'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM profiles
        WHERE id = (SELECT auth.uid())
        AND role = 'admin'
    )
);

-- DELETE politikası - Admin için
CREATE POLICY "courier_requests_delete_policy"
ON public.courier_requests FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles
        WHERE id = (SELECT auth.uid())
        AND role = 'admin'
    )
);

-- ============================================================================
-- 3. ADDRESSES TABLOSU - multiple_permissive DÜZELT
-- ============================================================================

-- Mevcut politikaları kaldır
DROP POLICY IF EXISTS "Users can view own addresses" ON public.addresses;
DROP POLICY IF EXISTS "sellers_view_order_addresses" ON public.addresses;

-- Tek bir SELECT politikası (OR ile birleştir)
CREATE POLICY "addresses_select_policy"
ON public.addresses FOR SELECT
TO authenticated
USING (
    -- Kullanıcı kendi adreslerini görebilir
    user_id = (SELECT auth.uid())
    OR
    -- Satıcılar sipariş adreslerini görebilir
    EXISTS (
        SELECT 1 FROM orders o
        JOIN shops s ON s.id = o.shop_id
        WHERE o.address_id = addresses.id
        AND s.owner_id = (SELECT auth.uid())
    )
);

-- ============================================================================
-- 4. SHOP_REVIEWS TABLOSU - multiple_permissive DÜZELT
-- ============================================================================

-- Mevcut politikaları kaldır
DROP POLICY IF EXISTS "Herkes yorumları görebilir" ON public.shop_reviews;
DROP POLICY IF EXISTS "Sellers can view their shop reviews" ON public.shop_reviews;
DROP POLICY IF EXISTS "Sellers can reply to their shop reviews" ON public.shop_reviews;
DROP POLICY IF EXISTS "Users can update own reviews" ON public.shop_reviews;

-- Tek bir SELECT politikası - herkes görebilir
CREATE POLICY "shop_reviews_select_policy"
ON public.shop_reviews FOR SELECT
USING (true);

-- Tek bir UPDATE politikası (OR ile birleştir)
CREATE POLICY "shop_reviews_update_policy"
ON public.shop_reviews FOR UPDATE
TO authenticated
USING (
    -- Kullanıcı kendi yorumunu güncelleyebilir (rating, comment)
    user_id = (SELECT auth.uid())
    OR
    -- Satıcı kendi mağazasının yorumlarına cevap verebilir (seller_reply)
    EXISTS (
        SELECT 1 FROM shops s
        WHERE s.id = shop_reviews.shop_id
        AND s.owner_id = (SELECT auth.uid())
    )
)
WITH CHECK (
    user_id = (SELECT auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM shops s
        WHERE s.id = shop_reviews.shop_id
        AND s.owner_id = (SELECT auth.uid())
    )
);

-- ============================================================================
-- 5. ONAY MESAJI
-- ============================================================================
SELECT 'RLS politikaları başarıyla optimize edildi!' as status;

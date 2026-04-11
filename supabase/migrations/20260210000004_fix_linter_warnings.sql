-- ============================================================================
-- SUPABASE LINTER FIXES - RLS Policy ve Function Optimizasyonları
-- ============================================================================
-- Sorunlar:
-- 1. auth.uid() her satırda yeniden hesaplanıyor → (select auth.uid()) kullanılmalı
-- 2. Fonksiyonlarda search_path eksik
-- 3. Çoklu permissive policies (performans problemi)

-- 1. RLS Policy Fix - auth.uid() → (select auth.uid())

-- Orders policies
DROP POLICY IF EXISTS "orders_insert_policy" ON public.orders;
CREATE POLICY "orders_insert_policy" ON public.orders
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
CREATE POLICY "orders_select_policy" ON public.orders
    FOR SELECT TO authenticated
    USING (user_id = (select auth.uid()) OR (select auth_is_admin()) = true);

DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;
CREATE POLICY "orders_update_policy" ON public.orders
    FOR UPDATE TO authenticated
    USING (user_id = (select auth.uid()) OR (select auth_is_admin()) = true)
    WITH CHECK (user_id = (select auth.uid()) OR (select auth_is_admin()) = true);

DROP POLICY IF EXISTS "orders_delete_policy" ON public.orders;
CREATE POLICY "orders_delete_policy" ON public.orders
    FOR DELETE TO authenticated
    USING (user_id = (select auth.uid()) OR (select auth_is_admin()) = true);

-- Products policies - Önce eski policies'i temizle
DROP POLICY IF EXISTS "products_select" ON public.products;
DROP POLICY IF EXISTS "products_select_policy" ON public.products;

-- Tek bir SELECT policy oluştur (shop_id üzerinden kontrol)
CREATE POLICY "products_select_policy" ON public.products
    FOR SELECT TO public
    USING (is_active = true OR EXISTS (
        SELECT 1 FROM public.shops
        WHERE shops.id = products.shop_id
        AND shops.owner_id = (select auth.uid())
    ) OR (select auth_is_admin()) = true);

DROP POLICY IF EXISTS "products_insert_policy" ON public.products;
CREATE POLICY "products_insert_policy" ON public.products
    FOR INSERT TO authenticated
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.shops
        WHERE shops.id = products.shop_id
        AND shops.owner_id = (select auth.uid())
    ));

DROP POLICY IF EXISTS "products_update_policy" ON public.products;
CREATE POLICY "products_update_policy" ON public.products
    FOR UPDATE TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.shops
        WHERE shops.id = products.shop_id
        AND shops.owner_id = (select auth.uid())
    ) OR (select auth_is_admin()) = true)
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.shops
        WHERE shops.id = products.shop_id
        AND shops.owner_id = (select auth.uid())
    ) OR (select auth_is_admin()) = true);

DROP POLICY IF EXISTS "products_delete_policy" ON public.products;
CREATE POLICY "products_delete_policy" ON public.products
    FOR DELETE TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.shops
        WHERE shops.id = products.shop_id
        AND shops.owner_id = (select auth.uid())
    ) OR (select auth_is_admin()) = true);

-- Shops policies - Önce eski policies'i temizle
DROP POLICY IF EXISTS "shops_select" ON public.shops;
DROP POLICY IF EXISTS "shops_select_policy" ON public.shops;

-- Tek bir SELECT policy oluştur
CREATE POLICY "shops_select_policy" ON public.shops
    FOR SELECT TO public
    USING (is_active = true OR owner_id = (select auth.uid()) OR (select auth_is_admin()) = true);

DROP POLICY IF EXISTS "shops_insert_policy" ON public.shops;
CREATE POLICY "shops_insert_policy" ON public.shops
    FOR INSERT TO authenticated
    WITH CHECK (owner_id = (select auth.uid()));

DROP POLICY IF EXISTS "shops_update_policy" ON public.shops;
CREATE POLICY "shops_update_policy" ON public.shops
    FOR UPDATE TO authenticated
    USING (owner_id = (select auth.uid()) OR (select auth_is_admin()) = true)
    WITH CHECK (owner_id = (select auth.uid()) OR (select auth_is_admin()) = true);

DROP POLICY IF EXISTS "shops_delete_policy" ON public.shops;
CREATE POLICY "shops_delete_policy" ON public.shops
    FOR DELETE TO authenticated
    USING (owner_id = (select auth.uid()) OR (select auth_is_admin()) = true);

-- Conversations policy
DROP POLICY IF EXISTS "conversations_insert_own" ON public.conversations;
CREATE POLICY "conversations_insert_own" ON public.conversations
    FOR INSERT TO authenticated
    WITH CHECK (
        user_id = (select auth.uid()) OR
        other_user_id = (select auth.uid())
    );

-- App about settings policy
DROP POLICY IF EXISTS "app_about_settings_update_policy" ON public.app_about_settings;
CREATE POLICY "app_about_settings_update_policy" ON public.app_about_settings
    FOR UPDATE TO authenticated
    USING ((select auth_is_admin()) = true)
    WITH CHECK ((select auth_is_admin()) = true);

-- 2. Function search_path fixes

DROP FUNCTION IF EXISTS public.update_post_comments_count CASCADE;
CREATE OR REPLACE FUNCTION public.update_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.posts
        SET comments_count = comments_count + 1
        WHERE id = NEW.post_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.posts
        SET comments_count = GREATEST(0, comments_count - 1)
        WHERE id = OLD.post_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

DROP FUNCTION IF EXISTS public.update_app_about_settings_updated_at CASCADE;
CREATE OR REPLACE FUNCTION public.update_app_about_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

DROP FUNCTION IF EXISTS public.get_email_settings(UUID) CASCADE;
CREATE OR REPLACE FUNCTION public.get_email_settings(p_user_id UUID)
RETURNS TABLE (
    email_notifications BOOLEAN,
    push_notifications BOOLEAN,
    order_notifications BOOLEAN,
    promotion_notifications BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(es.email_notifications, true),
        COALESCE(es.push_notifications, true),
        COALESCE(es.order_notifications, true),
        COALESCE(es.promotion_notifications, true)
    FROM public.email_settings es
    WHERE es.user_id = p_user_id;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

DO $$
BEGIN
    RAISE NOTICE 'Supabase linter fixes applied successfully!';
    RAISE NOTICE '- RLS policies optimized with (select auth.uid())';
    RAISE NOTICE '- Functions updated with search_path = public';
    RAISE NOTICE '- Duplicate SELECT policies merged';
END $$;

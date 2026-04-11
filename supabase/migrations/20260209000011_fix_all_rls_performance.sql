-- =============================================
-- Fix All RLS Performance Issues
-- =============================================
-- Tüm RLS politikalarındaki auth.uid() performans sorunlarını düzelt
-- Duplicate indexleri temizle

-- =============================================
-- 1. ORDERS - RLS Performans Fix
-- =============================================

-- Orders SELECT policy
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
CREATE POLICY "orders_select_policy" ON orders
    FOR SELECT
    TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR
        EXISTS (SELECT 1 FROM order_items oi JOIN shops s ON oi.shop_id = s.id WHERE oi.order_id = orders.id AND s.owner_id = (SELECT auth.uid())) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- Orders INSERT policy
DROP POLICY IF EXISTS "orders_insert_policy" ON orders;
CREATE POLICY "orders_insert_policy" ON orders
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));

-- Orders UPDATE policy
DROP POLICY IF EXISTS "orders_update_policy" ON orders;
CREATE POLICY "orders_update_policy" ON orders
    FOR UPDATE
    TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR
        EXISTS (SELECT 1 FROM order_items oi JOIN shops s ON oi.shop_id = s.id WHERE oi.order_id = orders.id AND s.owner_id = (SELECT auth.uid())) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    )
    WITH CHECK (
        user_id = (SELECT auth.uid()) OR
        EXISTS (SELECT 1 FROM order_items oi JOIN shops s ON oi.shop_id = s.id WHERE oi.order_id = orders.id AND s.owner_id = (SELECT auth.uid())) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- Orders DELETE policy
DROP POLICY IF EXISTS "orders_delete_policy" ON orders;
CREATE POLICY "orders_delete_policy" ON orders
    FOR DELETE
    TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- =============================================
-- 2. PROFILES - Multiple Policy Fix (Tek Bir Policy)
-- =============================================

-- Mevcut policies sil ve tek bir policy oluştur
DROP POLICY IF EXISTS "profiles_update" ON profiles;
DROP POLICY IF EXISTS "profiles_admin_update" ON profiles;

CREATE POLICY "profiles_update_policy" ON profiles
    FOR UPDATE
    TO authenticated
    USING (
        id = (SELECT auth.uid()) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    )
    WITH CHECK (
        id = (SELECT auth.uid()) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- =============================================
-- 3. Duplicate Indexleri Temizle
-- =============================================

-- follows tablosu - idx_follows_follower sil (idx_follows_follower_id kalsın)
DROP INDEX IF EXISTS idx_follows_follower;

-- follows tablosu - idx_follows_following sil (idx_follows_following_id kalsın)
DROP INDEX IF EXISTS idx_follows_following;

-- posts tablosu - idx_posts_user sil (idx_posts_user_id kalsın)
DROP INDEX IF EXISTS idx_posts_user;

-- products tablosu - idx_products_shop sil (idx_products_shop_id kalsın)
DROP INDEX IF EXISTS idx_products_shop;

-- =============================================
-- Doğrulama
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'RLS Performance Fixes Applied!';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✓ Orders RLS policies optimized';
    RAISE NOTICE '✓ Profiles UPDATE policy merged';
    RAISE NOTICE '✓ Duplicate indexes removed';
    RAISE NOTICE '========================================';
END $$;

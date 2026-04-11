-- ============================================================================
-- SUPABASE LINTER - TÜM PERFORMANS UYARILARINI DÜZELT
-- ============================================================================
-- Tarih: 2026-03-07
-- Amaç: 21 adet WARN seviyesindeki tüm linter uyarılarını düzelt
--
-- DÜZELTİLEN UYARILAR:
--   1. auth_rls_initplan (1 adet) - notifications tablosu
--   2. multiple_permissive_policies (20 adet) - 10 farklı tablo
--
-- PERFORMANS ETKİSİ:
--   - Her satır için auth fonksiyonu çağrısı optimize edildi
--   - Birden fazla policy yerine tek policy (query optimizer için daha iyi)
--   - Genel sorgu performansı artışı
--
-- NOT: ÖNCESİNDE BACKUP ALINMASI ŞİDDETLE ÖNERİLİR!
-- ============================================================================

BEGIN;

-- ============================================================================
-- BÖLÜM 1: AUTH_RLS_INITPLAN - NOTIFICATIONS
-- ============================================================================
-- Sorun: "Users can delete own notifications" policy'si auth.uid()'yi her satır için değerlendiriyor
-- Çözüm: (select auth.uid()) ile subquery kullan

DROP POLICY IF EXISTS "Users can delete own notifications" ON public.notifications;

CREATE POLICY "Users can delete own notifications"
ON public.notifications
FOR DELETE TO authenticated
USING (user_id = (select auth.uid()));

-- Diğer notifications policy'lerini de optimize et
DROP POLICY IF EXISTS "notifications_select" ON public.notifications;
CREATE POLICY "notifications_select"
ON public.notifications
FOR SELECT TO authenticated
USING (user_id = (select auth.uid()));

-- ============================================================================
-- BÖLÜM 2: MULTIPLE PERMISSIVE POLICIES - PRODUCTS (anon)
-- ============================================================================
-- Sorun: products tablosu anon role için SELECT'te 2 policy var
-- Policies: {products_select_active_anon, products_select_policy}

DROP POLICY IF EXISTS "products_select_active_anon" ON public.products;
DROP POLICY IF EXISTS "products_select_policy" ON public.products;

CREATE POLICY "products_select_anon_unified"
ON public.products
FOR SELECT TO anon
USING (
    is_active = true
    AND EXISTS (
        SELECT 1 FROM public.shops s
        WHERE s.id = products.shop_id
        AND s.is_active = true
    )
);

-- ============================================================================
-- BÖLÜM 3: MULTIPLE PERMISSIVE POLICIES - PRODUCTS (authenticated)
-- ============================================================================
-- Sorun: products tablosu authenticated role için SELECT'te 2 policy var
-- Policies: {products_select_active_or_owner, products_select_policy}

DROP POLICY IF EXISTS "products_select_active_or_owner" ON public.products;

CREATE POLICY "products_select_authenticated_unified"
ON public.products
FOR SELECT TO authenticated
USING (
    -- Aktif ürünleri herkes görebilir
    (is_active = true AND EXISTS (
        SELECT 1 FROM public.shops s
        WHERE s.id = products.shop_id
        AND s.is_active = true
    ))
    OR
    -- Veya dükkan sahibi kendi ürünlerini görebilir
    EXISTS (
        SELECT 1 FROM public.shops s
        WHERE s.id = products.shop_id
        AND s.owner_id = (select auth.uid())
    )
);

-- ============================================================================
-- BÖLÜM 4: MULTIPLE PERMISSIVE POLICIES - SHOPS (anon)
-- ============================================================================
-- Sorun: shops tablosu anon role için SELECT'te 2 policy var
-- Policies: {shops_select_active_anon, shops_select_policy}

DROP POLICY IF EXISTS "shops_select_active_anon" ON public.shops;
DROP POLICY IF EXISTS "shops_select_policy" ON public.shops;

CREATE POLICY "shops_select_anon_unified"
ON public.shops
FOR SELECT TO anon
USING (is_active = true AND is_approved = true);

-- ============================================================================
-- BÖLÜM 5: MULTIPLE PERMISSIVE POLICIES - SHOPS (authenticated)
-- ============================================================================
-- Sorun: shops tablosu authenticated role için SELECT/DELETE/UPDATE'te 2'şer policy var
-- Policies: 
--   SELECT: {shops_select_active_or_owner, shops_select_policy}
--   DELETE: {shops_delete_owner_or_admin, shops_delete_policy}
--   UPDATE: {shops_update_owner_or_admin, shops_update_policy}

DROP POLICY IF EXISTS "shops_select_active_or_owner" ON public.shops;
DROP POLICY IF EXISTS "shops_delete_owner_or_admin" ON public.shops;
DROP POLICY IF EXISTS "shops_delete_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_update_owner_or_admin" ON public.shops;
DROP POLICY IF EXISTS "shops_update_policy" ON public.shops;

-- SELECT unified
CREATE POLICY "shops_select_authenticated_unified"
ON public.shops
FOR SELECT TO authenticated
USING (
    (is_active = true AND is_approved = true)
    OR
    owner_id = (select auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM auth.users
        WHERE id = (select auth.uid())
        AND raw_user_meta_data->>'is_admin' = 'true'
    )
);

-- DELETE unified
CREATE POLICY "shops_delete_authenticated_unified"
ON public.shops
FOR DELETE TO authenticated
USING (
    owner_id = (select auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM auth.users
        WHERE id = (select auth.uid())
        AND raw_user_meta_data->>'is_admin' = 'true'
    )
);

-- UPDATE unified
CREATE POLICY "shops_update_authenticated_unified"
ON public.shops
FOR UPDATE TO authenticated
USING (
    owner_id = (select auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM auth.users
        WHERE id = (select auth.uid())
        AND raw_user_meta_data->>'is_admin' = 'true'
    )
)
WITH CHECK (
    owner_id = (select auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM auth.users
        WHERE id = (select auth.uid())
        AND raw_user_meta_data->>'is_admin' = 'true'
    )
);

-- ============================================================================
-- BÖLÜM 6: MULTIPLE PERMISSIVE POLICIES - ADDRESSES
-- ============================================================================
-- Sorun: addresses tablosu authenticated role için INSERT/SELECT'te 2'şer policy var
-- Policies:
--   INSERT: {"Users can insert own addresses", addresses_insert_own}
--   SELECT: {addresses_select_own, addresses_select_policy}

DROP POLICY IF EXISTS "Users can insert own addresses" ON public.addresses;
DROP POLICY IF EXISTS "addresses_insert_own" ON public.addresses;
DROP POLICY IF EXISTS "addresses_select_own" ON public.addresses;
DROP POLICY IF EXISTS "addresses_select_policy" ON public.addresses;

-- INSERT unified
CREATE POLICY "addresses_insert_unified"
ON public.addresses
FOR INSERT TO authenticated
WITH CHECK (user_id = (select auth.uid()));

-- SELECT unified
CREATE POLICY "addresses_select_unified"
ON public.addresses
FOR SELECT TO authenticated
USING (user_id = (select auth.uid()));

-- ============================================================================
-- BÖLÜM 7: MULTIPLE PERMISSIVE POLICIES - CART_ITEMS
-- ============================================================================
-- Sorun: cart_items tablosu authenticated role için DELETE/INSERT/SELECT/UPDATE'te 2'şer policy var
-- Policies:
--   DELETE: {cart_items_all_own, cart_items_delete_policy}
--   INSERT: {cart_items_all_own, cart_items_insert_policy}
--   SELECT: {cart_items_all_own, cart_items_select_policy}
--   UPDATE: {cart_items_all_own, cart_items_update_policy}

DROP POLICY IF EXISTS "cart_items_all_own" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_delete_policy" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_insert_policy" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_select_policy" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_update_policy" ON public.cart_items;

-- DELETE unified
CREATE POLICY "cart_items_delete_unified"
ON public.cart_items
FOR DELETE TO authenticated
USING (user_id = (select auth.uid()));

-- INSERT unified
CREATE POLICY "cart_items_insert_unified"
ON public.cart_items
FOR INSERT TO authenticated
WITH CHECK (user_id = (select auth.uid()));

-- SELECT unified
CREATE POLICY "cart_items_select_unified"
ON public.cart_items
FOR SELECT TO authenticated
USING (user_id = (select auth.uid()));

-- UPDATE unified
CREATE POLICY "cart_items_update_unified"
ON public.cart_items
FOR UPDATE TO authenticated
USING (user_id = (select auth.uid()))
WITH CHECK (user_id = (select auth.uid()));

-- ============================================================================
-- BÖLÜM 8: MULTIPLE PERMISSIVE POLICIES - NOTIFICATIONS
-- ============================================================================
-- Sorun: notifications tablosu authenticated role için DELETE/INSERT/UPDATE'te 2'şer policy var
-- Policies:
--   DELETE: {"Users can delete own notifications", notifications_delete}
--   INSERT: {notifications_insert, notifications_insert_policy_proper}
--   UPDATE: {notifications_update, notifications_update_unified}

DROP POLICY IF EXISTS "notifications_delete" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_policy_proper" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update_unified" ON public.notifications;

-- DELETE zaten yukarıda düzeltildi (auth_rls_initplan kısmında)

-- INSERT unified - INTENTIONALLY PERMISSIVE
CREATE POLICY "notifications_insert_final"
ON public.notifications
FOR INSERT TO authenticated
WITH CHECK (true);

COMMENT ON POLICY "notifications_insert_final" ON public.notifications IS 
'INTENTIONALLY PERMISSIVE: System notifications, order updates, triggers require cross-user notification creation';

-- UPDATE unified
CREATE POLICY "notifications_update_final"
ON public.notifications
FOR UPDATE TO authenticated
USING (user_id = (select auth.uid()))
WITH CHECK (user_id = (select auth.uid()));

-- ============================================================================
-- BÖLÜM 9: MULTIPLE PERMISSIVE POLICIES - ORDERS
-- ============================================================================
-- Sorun: orders tablosu authenticated role için SELECT'te 2 policy var
-- Policies: {orders_select_policy, orders_select_user_or_seller_or_admin}

DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_select_user_or_seller_or_admin" ON public.orders;

-- SELECT unified
CREATE POLICY "orders_select_unified"
ON public.orders
FOR SELECT TO authenticated
USING (
    -- Kullanıcı kendi siparişlerini görebilir
    user_id = (select auth.uid())
    OR
    -- Dükkan sahibi kendi dükkanının siparişlerini görebilir
    EXISTS (
        SELECT 1 FROM public.shops s
        WHERE s.id = orders.shop_id
        AND s.owner_id = (select auth.uid())
    )
    OR
    -- Admin tüm siparişleri görebilir
    EXISTS (
        SELECT 1 FROM auth.users
        WHERE id = (select auth.uid())
        AND raw_user_meta_data->>'is_admin' = 'true'
    )
);

-- ============================================================================
-- BÖLÜM 10: MULTIPLE PERMISSIVE POLICIES - POSTS
-- ============================================================================
-- Sorun: posts tablosu authenticated role için DELETE/INSERT'te 2'şer policy var
-- Policies:
--   DELETE: {posts_delete_own, posts_delete_policy}
--   INSERT: {posts_insert, posts_insert_own}

DROP POLICY IF EXISTS "posts_delete_own" ON public.posts;
DROP POLICY IF EXISTS "posts_delete_policy" ON public.posts;
DROP POLICY IF EXISTS "posts_insert" ON public.posts;
DROP POLICY IF EXISTS "posts_insert_own" ON public.posts;

-- DELETE unified
CREATE POLICY "posts_delete_unified"
ON public.posts
FOR DELETE TO authenticated
USING (
    user_id = (select auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM auth.users
        WHERE id = (select auth.uid())
        AND raw_user_meta_data->>'is_admin' = 'true'
    )
);

-- INSERT unified
CREATE POLICY "posts_insert_unified"
ON public.posts
FOR INSERT TO authenticated
WITH CHECK (user_id = (select auth.uid()));

-- ============================================================================
-- BÖLÜM 11: MULTIPLE PERMISSIVE POLICIES - PROFILES
-- ============================================================================
-- Sorun: profiles tablosu authenticated role için UPDATE'te 2 policy var
-- Policies: {profiles_update_own, profiles_update_policy}

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_policy" ON public.profiles;

-- UPDATE unified
CREATE POLICY "profiles_update_unified"
ON public.profiles
FOR UPDATE TO authenticated
USING (id = (select auth.uid()))
WITH CHECK (id = (select auth.uid()));

-- ============================================================================
-- BÖLÜM 12: DOĞRULAMA VE RAPOR
-- ============================================================================

DO $$
DECLARE
    v_products_anon_count INT;
    v_products_auth_count INT;
    v_shops_anon_count INT;
    v_shops_auth_select_count INT;
    v_shops_auth_delete_count INT;
    v_shops_auth_update_count INT;
    v_addresses_insert_count INT;
    v_addresses_select_count INT;
    v_cart_delete_count INT;
    v_cart_insert_count INT;
    v_cart_select_count INT;
    v_cart_update_count INT;
    v_notif_delete_count INT;
    v_notif_insert_count INT;
    v_notif_update_count INT;
    v_orders_select_count INT;
    v_posts_delete_count INT;
    v_posts_insert_count INT;
    v_profiles_update_count INT;
BEGIN
    -- Policy sayılarını kontrol et
    SELECT COUNT(*) INTO v_products_anon_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'products'
    AND policyname LIKE '%select%' AND roles::text LIKE '%anon%';

    SELECT COUNT(*) INTO v_products_auth_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'products'
    AND policyname LIKE '%select%' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_shops_anon_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'shops'
    AND policyname LIKE '%select%' AND roles::text LIKE '%anon%';

    SELECT COUNT(*) INTO v_shops_auth_select_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'shops'
    AND policyname LIKE '%select%' AND cmd = 'SELECT' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_shops_auth_delete_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'shops'
    AND cmd = 'DELETE' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_shops_auth_update_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'shops'
    AND cmd = 'UPDATE' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_addresses_insert_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'addresses'
    AND cmd = 'INSERT' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_addresses_select_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'addresses'
    AND cmd = 'SELECT' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_cart_delete_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'cart_items'
    AND cmd = 'DELETE' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_cart_insert_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'cart_items'
    AND cmd = 'INSERT' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_cart_select_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'cart_items'
    AND cmd = 'SELECT' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_cart_update_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'cart_items'
    AND cmd = 'UPDATE' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_notif_delete_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'notifications'
    AND cmd = 'DELETE' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_notif_insert_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'notifications'
    AND cmd = 'INSERT' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_notif_update_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'notifications'
    AND cmd = 'UPDATE' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_orders_select_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'orders'
    AND cmd = 'SELECT' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_posts_delete_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'posts'
    AND cmd = 'DELETE' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_posts_insert_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'posts'
    AND cmd = 'INSERT' AND roles::text LIKE '%authenticated%';

    SELECT COUNT(*) INTO v_profiles_update_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
    AND cmd = 'UPDATE' AND roles::text LIKE '%authenticated%';

    -- Rapor
    RAISE NOTICE '';
    RAISE NOTICE '========================================================================';
    RAISE NOTICE '    SUPABASE LINTER - PERFORMANS UYARILARI DÜZELTME RAPORU';
    RAISE NOTICE '========================================================================';
    RAISE NOTICE '';
    RAISE NOTICE '✅ AUTH_RLS_INITPLAN düzeltildi:';
    RAISE NOTICE '   notifications: auth.uid() -> (select auth.uid())';
    RAISE NOTICE '';
    RAISE NOTICE '✅ MULTIPLE PERMISSIVE POLICIES düzeltildi:';
    RAISE NOTICE '';
    RAISE NOTICE '   products (anon SELECT): % policy (hedef: 1)', v_products_anon_count;
    RAISE NOTICE '   products (auth SELECT): % policy (hedef: 1)', v_products_auth_count;
    RAISE NOTICE '   shops (anon SELECT): % policy (hedef: 1)', v_shops_anon_count;
    RAISE NOTICE '   shops (auth SELECT): % policy (hedef: 1)', v_shops_auth_select_count;
    RAISE NOTICE '   shops (auth DELETE): % policy (hedef: 1)', v_shops_auth_delete_count;
    RAISE NOTICE '   shops (auth UPDATE): % policy (hedef: 1)', v_shops_auth_update_count;
    RAISE NOTICE '   addresses (auth INSERT): % policy (hedef: 1)', v_addresses_insert_count;
    RAISE NOTICE '   addresses (auth SELECT): % policy (hedef: 1)', v_addresses_select_count;
    RAISE NOTICE '   cart_items (auth DELETE): % policy (hedef: 1)', v_cart_delete_count;
    RAISE NOTICE '   cart_items (auth INSERT): % policy (hedef: 1)', v_cart_insert_count;
    RAISE NOTICE '   cart_items (auth SELECT): % policy (hedef: 1)', v_cart_select_count;
    RAISE NOTICE '   cart_items (auth UPDATE): % policy (hedef: 1)', v_cart_update_count;
    RAISE NOTICE '   notifications (auth DELETE): % policy (hedef: 1)', v_notif_delete_count;
    RAISE NOTICE '   notifications (auth INSERT): % policy (hedef: 1)', v_notif_insert_count;
    RAISE NOTICE '   notifications (auth UPDATE): % policy (hedef: 1)', v_notif_update_count;
    RAISE NOTICE '   orders (auth SELECT): % policy (hedef: 1)', v_orders_select_count;
    RAISE NOTICE '   posts (auth DELETE): % policy (hedef: 1)', v_posts_delete_count;
    RAISE NOTICE '   posts (auth INSERT): % policy (hedef: 1)', v_posts_insert_count;
    RAISE NOTICE '   profiles (auth UPDATE): % policy (hedef: 1)', v_profiles_update_count;
    RAISE NOTICE '';
    RAISE NOTICE '========================================================================';
    RAISE NOTICE '    SONRAKI ADIMLAR';
    RAISE NOTICE '========================================================================';
    RAISE NOTICE '';
    RAISE NOTICE '1. Supabase Dashboard > Database > Linter çalıştır';
    RAISE NOTICE '2. Tüm WARN uyarılarının gittiğini doğrula';
    RAISE NOTICE '3. Uygulama fonksiyonlarını test et (CRUD işlemleri)';
    RAISE NOTICE '4. Performans artışını gözlemle';
    RAISE NOTICE '';
    RAISE NOTICE '========================================================================';
    RAISE NOTICE '';
END $$;

COMMIT;

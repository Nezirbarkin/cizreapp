-- =============================================
-- Admin Dashboard için Ek RLS Politikaları
-- =============================================
-- Mevcut politikaları koruyarak admin kullanıcısına tüm verileri görme izni

-- Önce mevcut admin politikalarını sil (varsa)
DROP POLICY IF EXISTS "profiles_admin_select_all" ON profiles;
DROP POLICY IF EXISTS "posts_admin_select_all" ON posts;
DROP POLICY IF EXISTS "products_admin_select_all" ON products;
DROP POLICY IF EXISTS "orders_admin_select_all" ON orders;
DROP POLICY IF EXISTS "shops_admin_select_all" ON shops;
DROP POLICY IF EXISTS "order_items_admin_select_all" ON order_items;

-- 1. PROFILES - Admin için ek select politikası
CREATE POLICY "profiles_admin_select_all" ON profiles
    FOR SELECT
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 2. POSTS - Admin için ek select politikası  
CREATE POLICY "posts_admin_select_all" ON posts
    FOR SELECT
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 3. PRODUCTS - Admin için ek select politikası
CREATE POLICY "products_admin_select_all" ON products
    FOR SELECT
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 4. ORDERS - Admin için ek select politikası
CREATE POLICY "orders_admin_select_all" ON orders
    FOR SELECT
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 5. SHOPS - Admin için ek select politikası
CREATE POLICY "shops_admin_select_all" ON shops
    FOR SELECT
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 6. ORDER_ITEMS - Admin için ek select politikası
CREATE POLICY "order_items_admin_select_all" ON order_items
    FOR SELECT
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- Doğrulama
DO $$
DECLARE
    v_admin_count INT;
    v_user_count INT;
    v_post_count INT;
    v_product_count INT;
    v_order_count INT;
BEGIN
    SELECT COUNT(*) INTO v_admin_count FROM profiles WHERE role = 'admin';
    SELECT COUNT(*) INTO v_user_count FROM profiles;
    SELECT COUNT(*) INTO v_post_count FROM posts;
    SELECT COUNT(*) INTO v_product_count FROM products;
    SELECT COUNT(*) INTO v_order_count FROM orders;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Admin Dashboard RLS Policies Added!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Admin users: %', v_admin_count;
    RAISE NOTICE 'Total users: %', v_user_count;
    RAISE NOTICE 'Total posts: %', v_post_count;
    RAISE NOTICE 'Total products: %', v_product_count;
    RAISE NOTICE 'Total orders: %', v_order_count;
    RAISE NOTICE '========================================';
END $$;

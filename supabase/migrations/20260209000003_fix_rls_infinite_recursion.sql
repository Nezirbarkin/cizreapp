-- =============================================
-- Fix Infinite Recursion in Profiles RLS
-- =============================================
-- Profil politikası kendi içinde profiles'a sorgu yaparken sonsuz döngü oluşturdu
-- Bu migration bunu düzeltir

-- 1. Önce RLS'i geçici olarak devre dışı bırak
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- 2. Tüm profiles politikalarını sil
DROP POLICY IF EXISTS "profiles_select_policy" ON profiles;
DROP POLICY IF EXISTS "profiles_admin_select_all" ON profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
DROP POLICY IF EXISTS "profiles_insert_new" ON profiles;
DROP POLICY IF EXISTS "Enable read access for all users" ON profiles;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON profiles;
DROP POLICY IF EXISTS "Enable update for users based on id" ON profiles;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone." ON profiles;
DROP POLICY IF EXISTS "profiles_public_read" ON profiles;
DROP POLICY IF EXISTS "Users can view all profiles" ON profiles;

-- 3. Basit ve güvenli politikalar oluştur
-- Herkes tüm profilleri görebilir (anonim ve authenticated)
CREATE POLICY "profiles_select_all" ON profiles
    FOR SELECT
    USING (true);

-- Kullanıcılar sadece kendi profillerini güncelleyebilir
CREATE POLICY "profiles_update_own" ON profiles
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Yeni kullanıcılar kendi profillerini oluşturabilir
CREATE POLICY "profiles_insert_own" ON profiles
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);

-- Admin kullanıcılar profil silebilir
CREATE POLICY "profiles_delete_admin" ON profiles
    FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM auth.users u 
            JOIN profiles p ON p.id = u.id 
            WHERE u.id = auth.uid() AND p.role = 'admin'
        )
    );

-- 4. RLS'i tekrar etkinleştir
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 5. Diğer tablolardaki admin kontrollerini de security definer function ile düzelt
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
    RETURN v_role = 'admin';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6. Posts politikasını düzelt
DROP POLICY IF EXISTS "posts_select_policy" ON posts;
DROP POLICY IF EXISTS "posts_admin_select_all" ON posts;
CREATE POLICY "posts_select_all" ON posts
    FOR SELECT
    USING (true);

-- 7. Products politikasını düzelt
DROP POLICY IF EXISTS "products_select_policy" ON products;
DROP POLICY IF EXISTS "products_admin_select_all" ON products;
CREATE POLICY "products_select_all" ON products
    FOR SELECT
    USING (true);

-- 8. Shops politikasını düzelt
DROP POLICY IF EXISTS "shops_select_policy" ON shops;
DROP POLICY IF EXISTS "shops_admin_select_all" ON shops;
CREATE POLICY "shops_select_all" ON shops
    FOR SELECT
    USING (true);

-- 9. Orders politikasını düzelt (hassas veri - daha kısıtlı)
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
DROP POLICY IF EXISTS "orders_admin_select_all" ON orders;
CREATE POLICY "orders_select" ON orders
    FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR
        is_admin() OR
        EXISTS (SELECT 1 FROM order_items oi JOIN shops s ON oi.shop_id = s.id WHERE oi.order_id = orders.id AND s.owner_id = auth.uid())
    );

-- 10. Order items politikasını düzelt
DROP POLICY IF EXISTS "order_items_admin_select_all" ON order_items;
DROP POLICY IF EXISTS "order_items_select_policy" ON order_items;
CREATE POLICY "order_items_select" ON order_items
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (SELECT 1 FROM orders WHERE id = order_items.order_id AND user_id = auth.uid()) OR
        is_admin() OR
        EXISTS (SELECT 1 FROM shops WHERE id = order_items.shop_id AND owner_id = auth.uid())
    );

-- Doğrulama
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Profiles RLS Infinite Recursion FIXED!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'All profiles are now readable by everyone';
    RAISE NOTICE 'is_admin() function created for safe admin checks';
END $$;

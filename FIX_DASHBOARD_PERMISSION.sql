-- ==============================================================================
-- FIX: Admin Dashboard Permission Denied Hatası
-- ==============================================================================
-- Hata: PostgrestException(message: permission denied for table users, code: 42501)
-- Çözüm: Tüm dashboard tablolarının RLS policy'lerini düzelt
-- ==============================================================================

-- 1. Önce mevcut durumları kontrol et
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename IN ('profiles', 'posts', 'products', 'orders', 'user_reports', 'support_tickets')
ORDER BY tablename, policyname;

-- ==============================================================================
-- 2. PROFILES TABLOSU - auth.users erişimini kaldır
-- ==============================================================================

DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_authenticated_select_policy" ON public.profiles;
DROP POLICY IF EXISTS "profiles_public_select_policy" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_delete_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_all" ON public.profiles;
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.profiles;

-- Temiz policy'ler oluştur
CREATE POLICY "profiles_select_public"
ON public.profiles
FOR SELECT
TO public, authenticated
USING (true);

CREATE POLICY "profiles_insert_own"
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_update_own"
ON public.profiles
FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_delete_own"
ON public.profiles
FOR DELETE
TO authenticated
USING (id = auth.uid());

-- ==============================================================================
-- 3. POSTS TABLOSU - Dashboard için SELECT izni
-- ==============================================================================

-- Mevcut policy'leri kontrol et ve temizle
DROP POLICY IF EXISTS "posts_select_policy" ON public.posts;
DROP POLICY IF EXISTS "posts_insert_policy" ON public.posts;
DROP POLICY IF EXISTS "posts_update_policy" ON public.posts;
DROP POLICY IF EXISTS "posts_delete_policy" ON public.posts;
DROP POLICY IF EXISTS "Users can view their own posts" ON public.posts;
DROP POLICY IF EXISTS "Users can insert their own posts" ON public.posts;
DROP POLICY IF EXISTS "Users can update their own posts" ON public.posts;
DROP POLICY IF EXISTS "Users can delete their own posts" ON public.posts;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.posts;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON public.posts;
DROP POLICY IF EXISTS "Enable update for users based on id" ON public.posts;
DROP POLICY IF EXISTS "Enable delete for users based on id" ON public.posts;

-- Yeni temiz policy'ler
CREATE POLICY "posts_select_public"
ON public.posts
FOR SELECT
TO public, authenticated
USING (true);

CREATE POLICY "posts_insert_own"
ON public.posts
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "posts_update_own"
ON public.posts
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "posts_delete_own"
ON public.posts
FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- ==============================================================================
-- 4. PRODUCTS TABLOSU - Dashboard için SELECT izni
-- ==============================================================================

DROP POLICY IF EXISTS "products_select_policy" ON public.products;
DROP POLICY IF EXISTS "products_insert_policy" ON public.products;
DROP POLICY IF EXISTS "products_update_policy" ON public.products;
DROP POLICY IF EXISTS "products_delete_policy" ON public.products;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.products;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON public.products;
DROP POLICY IF EXISTS "Enable update for users based on id" ON public.products;
DROP POLICY IF EXISTS "Enable delete for users based on users_id" ON public.products;

CREATE POLICY "products_select_public"
ON public.products
FOR SELECT
TO public, authenticated
USING (true);

CREATE POLICY "products_insert_own"
ON public.products
FOR INSERT
TO authenticated
WITH CHECK (shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid()));

CREATE POLICY "products_update_own"
ON public.products
FOR UPDATE
TO authenticated
USING (shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid()));

CREATE POLICY "products_delete_own"
ON public.products
FOR DELETE
TO authenticated
USING (shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid()));

-- ==============================================================================
-- 5. ORDERS TABLOSU - Dashboard için SELECT izni
-- ==============================================================================

DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.orders;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON public.orders;
DROP POLICY IF EXISTS "Enable update for users based on users_id" ON public.orders;

CREATE POLICY "orders_select_public"
ON public.orders
FOR SELECT
TO public, authenticated
USING (true);

CREATE POLICY "orders_insert_own"
ON public.orders
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "orders_update_own"
ON public.orders
FOR UPDATE
TO authenticated
USING (user_id = auth.uid() OR shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid()))
WITH CHECK (user_id = auth.uid() OR shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid()));

-- ==============================================================================
-- 6. USER_REPORTS TABLOSU - Dashboard için SELECT izni
-- ==============================================================================

DROP POLICY IF EXISTS "user_reports_select_policy" ON public.user_reports;
DROP POLICY IF EXISTS "user_reports_insert_policy" ON public.user_reports;
DROP POLICY IF EXISTS "user_reports_update_policy" ON public.user_reports;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.user_reports;

CREATE POLICY "user_reports_select_public"
ON public.user_reports
FOR SELECT
TO public, authenticated
USING (true);

CREATE POLICY "user_reports_insert_own"
ON public.user_reports
FOR INSERT
TO authenticated
WITH CHECK (reporter_id = auth.uid());

CREATE POLICY "user_reports_update_admin"
ON public.user_reports
FOR UPDATE
TO authenticated
USING (auth.uid() IN (SELECT id FROM profiles WHERE is_admin = true));

-- ==============================================================================
-- 7. SUPPORT_TICKETS TABLOSU - Dashboard için SELECT izni
-- ==============================================================================

DROP POLICY IF EXISTS "support_tickets_select_policy" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_insert_policy" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_update_policy" ON public.support_tickets;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.support_tickets;

CREATE POLICY "support_tickets_select_authenticated"
ON public.support_tickets
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "support_tickets_insert_own"
ON public.support_tickets
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "support_tickets_update_own"
ON public.support_tickets
FOR UPDATE
TO authenticated
USING (user_id = auth.uid() OR auth.uid() IN (SELECT id FROM profiles WHERE is_admin = true));

-- ==============================================================================
-- 8. KONTROL - Policy'lerin oluşturulduğunu doğrula
-- ==============================================================================

DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count 
    FROM pg_policies 
    WHERE tablename IN ('profiles', 'posts', 'products', 'orders', 'user_reports', 'support_tickets');
    
    RAISE NOTICE '✅ Dashboard tabloları için % policy''leri oluşturuldu', v_count;
    RAISE NOTICE '✅ profiles: SELECT, INSERT, UPDATE, DELETE policy''leri hazır';
    RAISE NOTICE '✅ posts: SELECT, INSERT, UPDATE, DELETE policy''leri hazır';
    RAISE NOTICE '✅ products: SELECT, INSERT, UPDATE, DELETE policy''leri hazır';
    RAISE NOTICE '✅ orders: SELECT, INSERT, UPDATE policy''leri hazır';
    RAISE NOTICE '✅ user_reports: SELECT, INSERT, UPDATE policy''leri hazır';
    RAISE NOTICE '✅ support_tickets: SELECT, INSERT, UPDATE policy''leri hazır';
    RAISE NOTICE '✅ auth.users erişimi kaldırıldı, sadece auth.uid() kullanılıyor';
END $$;

-- ==============================================================================
-- 9. Son kontrol - Tablo ve policy durumları
-- ==============================================================================

SELECT 
    'profiles' as table_name,
    COUNT(*) FILTER (WHERE cmd = 'SELECT') as select_policies,
    COUNT(*) FILTER (WHERE cmd = 'INSERT') as insert_policies,
    COUNT(*) FILTER (WHERE cmd = 'UPDATE') as update_policies,
    COUNT(*) FILTER (WHERE cmd = 'DELETE') as delete_policies
FROM pg_policies WHERE tablename = 'profiles'
UNION ALL
SELECT 
    'posts',
    COUNT(*) FILTER (WHERE cmd = 'SELECT'),
    COUNT(*) FILTER (WHERE cmd = 'INSERT'),
    COUNT(*) FILTER (WHERE cmd = 'UPDATE'),
    COUNT(*) FILTER (WHERE cmd = 'DELETE')
FROM pg_policies WHERE tablename = 'posts'
UNION ALL
SELECT 
    'products',
    COUNT(*) FILTER (WHERE cmd = 'SELECT'),
    COUNT(*) FILTER (WHERE cmd = 'INSERT'),
    COUNT(*) FILTER (WHERE cmd = 'UPDATE'),
    COUNT(*) FILTER (WHERE cmd = 'DELETE')
FROM pg_policies WHERE tablename = 'products'
UNION ALL
SELECT 
    'orders',
    COUNT(*) FILTER (WHERE cmd = 'SELECT'),
    COUNT(*) FILTER (WHERE cmd = 'INSERT'),
    COUNT(*) FILTER (WHERE cmd = 'UPDATE'),
    COUNT(*) FILTER (WHERE cmd = 'DELETE')
FROM pg_policies WHERE tablename = 'orders'
ORDER BY table_name;

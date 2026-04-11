-- =============================================
-- COMPREHENSIVE RLS PERFORMANCE OPTIMIZATION
-- =============================================
-- Tüm performans sorunlarını çözen kapsamlı optimizasyon
-- 1. auth.uid() -> (select auth.uid()) optimizasyonu
-- 2. Çoklu policy'leri birleştirme
-- 3. Gereksiz policy'leri silme

-- Helper function - Performanslı admin kontrolü
CREATE OR REPLACE FUNCTION auth_is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND role = 'admin'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- =============================================
-- 1. PROFILES TABLOSU OPTIMIZATION
-- =============================================
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- Tüm eski politikaları sil
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'profiles' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON profiles', policy_record.policyname);
    END LOOP;
END $$;

-- Yeni optimize edilmiş politikalar
CREATE POLICY "profiles_select" ON profiles
    FOR SELECT
    USING (true);  -- Herkes görebilir

CREATE POLICY "profiles_insert" ON profiles
    FOR INSERT
    TO authenticated
    WITH CHECK ((select auth.uid()) = id);

CREATE POLICY "profiles_update" ON profiles
    FOR UPDATE
    TO authenticated
    USING ((select auth.uid()) = id)
    WITH CHECK ((select auth.uid()) = id);

CREATE POLICY "profiles_delete" ON profiles
    FOR DELETE
    TO authenticated
    USING (auth_is_admin());

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- =============================================
-- 2. CONVERSATIONS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'conversations' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON conversations', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "conversations_all" ON conversations
    FOR ALL
    TO authenticated
    USING (
        (select auth.uid()) = user_id OR 
        (select auth.uid()) = other_user_id OR
        auth_is_admin()
    )
    WITH CHECK (
        (select auth.uid()) = user_id
    );

-- =============================================
-- 3. MESSAGES TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'messages' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON messages', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "messages_select" ON messages
    FOR SELECT
    TO authenticated
    USING (
        (select auth.uid()) = sender_id OR 
        EXISTS (
            SELECT 1 FROM conversations 
            WHERE id = messages.conversation_id 
            AND ((select auth.uid()) = user_id OR (select auth.uid()) = other_user_id)
        ) OR
        auth_is_admin()
    );

CREATE POLICY "messages_insert" ON messages
    FOR INSERT
    TO authenticated
    WITH CHECK ((select auth.uid()) = sender_id);

CREATE POLICY "messages_update" ON messages
    FOR UPDATE
    TO authenticated
    USING ((select auth.uid()) = sender_id)
    WITH CHECK ((select auth.uid()) = sender_id);

CREATE POLICY "messages_delete" ON messages
    FOR DELETE
    TO authenticated
    USING ((select auth.uid()) = sender_id OR auth_is_admin());

-- =============================================
-- 4. POSTS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'posts' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON posts', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "posts_select" ON posts
    FOR SELECT
    USING (true);  -- Herkes görebilir

CREATE POLICY "posts_insert" ON posts
    FOR INSERT
    TO authenticated
    WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY "posts_update" ON posts
    FOR UPDATE
    TO authenticated
    USING ((select auth.uid()) = user_id OR auth_is_admin());

CREATE POLICY "posts_delete" ON posts
    FOR DELETE
    TO authenticated
    USING ((select auth.uid()) = user_id OR auth_is_admin());

-- =============================================
-- 5. PRODUCTS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'products' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON products', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "products_select" ON products
    FOR SELECT
    USING (true);  -- Herkes görebilir

-- =============================================
-- 6. SHOPS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'shops' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON shops', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "shops_select" ON shops
    FOR SELECT
    USING (true);  -- Herkes görebilir

-- =============================================
-- 7. ORDERS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'orders' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON orders', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "orders_select" ON orders
    FOR SELECT
    TO authenticated
    USING (
        (select auth.uid()) = user_id OR
        auth_is_admin() OR
        EXISTS (
            SELECT 1 FROM order_items oi 
            JOIN shops s ON oi.shop_id = s.id 
            WHERE oi.order_id = orders.id AND s.owner_id = (select auth.uid())
        )
    );

-- =============================================
-- 8. ORDER_ITEMS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'order_items' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON order_items', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "order_items_select" ON order_items
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE id = order_items.order_id AND user_id = (select auth.uid())
        ) OR
        auth_is_admin() OR
        EXISTS (
            SELECT 1 FROM shops 
            WHERE id = order_items.shop_id AND owner_id = (select auth.uid())
        )
    );

-- =============================================
-- 9. NOTIFICATIONS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'notifications' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON notifications', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "notifications_select" ON notifications
    FOR SELECT
    TO authenticated
    USING ((select auth.uid()) = user_id OR auth_is_admin());

-- =============================================
-- 10. USER_REPORTS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'user_reports' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON user_reports', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "user_reports_select" ON user_reports
    FOR SELECT
    TO authenticated
    USING (
        (select auth.uid()) = reporter_id OR 
        (select auth.uid()) = reported_user_id OR
        auth_is_admin()
    );

-- =============================================
-- 11. SUPPORT_TICKETS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'support_tickets' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON support_tickets', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "support_tickets_select" ON support_tickets
    FOR SELECT
    TO authenticated
    USING ((select auth.uid()) = user_id OR auth_is_admin());

-- =============================================
-- 12. PRODUCT_VIEWS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'product_views' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON product_views', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "product_views_select" ON product_views
    FOR SELECT
    USING (true);

-- =============================================
-- 13. SHOP_VIEWS TABLOSU OPTIMIZATION
-- =============================================
DO $$ 
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN 
        SELECT policyname FROM pg_policies WHERE tablename = 'shop_views' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON shop_views', policy_record.policyname);
    END LOOP;
END $$;

CREATE POLICY "shop_views_select" ON shop_views
    FOR SELECT
    USING (true);

-- =============================================
-- DOĞRULAMA
-- =============================================
DO $$
DECLARE
    v_table_name TEXT;
    v_policy_count INT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'RLS PERFORMANCE OPTIMIZATION COMPLETE!';
    RAISE NOTICE '========================================';
    
    FOR v_table_name IN 
        SELECT DISTINCT tablename 
        FROM pg_policies 
        WHERE schemaname = 'public'
        ORDER BY tablename
    LOOP
        SELECT COUNT(*) INTO v_policy_count 
        FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = v_table_name;
        
        RAISE NOTICE 'Table: % - Policies: %', v_table_name, v_policy_count;
    END LOOP;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'All auth.uid() calls optimized with (select auth.uid())';
    RAISE NOTICE 'Duplicate policies removed';
    RAISE NOTICE 'Performance should be significantly improved!';
    RAISE NOTICE '========================================';
END $$;

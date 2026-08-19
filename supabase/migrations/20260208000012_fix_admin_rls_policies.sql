-- =============================================
-- Fix Admin RLS Policies for Dashboard Real Data
-- =============================================
-- Admin kullanıcısının dashboard'da gerçek verileri görmesi için RLS politikaları

-- 1. PROFILES - Admin tüm kullanıcıları görebilmeli
DROP POLICY IF EXISTS "profiles_select_policy" ON profiles;
CREATE POLICY "profiles_select_policy" ON profiles
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() = id OR 
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 2. POSTS - Admin tüm gönderileri görebilmeli
DROP POLICY IF EXISTS "posts_select_policy" ON posts;
CREATE POLICY "posts_select_policy" ON posts
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() = user_id OR 
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 3. PRODUCTS - Admin tüm ürünleri görebilmeli
DROP POLICY IF EXISTS "products_select_policy" ON products;
CREATE POLICY "products_select_policy" ON products
    FOR SELECT
    TO authenticated
    USING (
        shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid()) OR
        (SELECT role FROM profiles WHERE id = auth.uid()) IN ('admin', 'seller')
    );

-- 4. ORDERS - Admin tüm siparişleri görebilmeli
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
CREATE POLICY "orders_select_policy" ON orders
    FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR
        EXISTS (SELECT 1 FROM order_items oi JOIN shops s ON oi.shop_id = s.id WHERE oi.order_id = orders.id AND s.owner_id = auth.uid()) OR
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 5. SHOPS - Admin tüm mağazaları görebilmeli
DROP POLICY IF EXISTS "shops_select_policy" ON shops;
CREATE POLICY "shops_select_policy" ON shops
    FOR SELECT
    TO authenticated
    USING (
        owner_id = auth.uid() OR 
        (SELECT role FROM profiles WHERE id = auth.uid()) IN ('admin', 'seller')
    );

-- 6. USER_REPORTS - Admin tüm raporları görebilmeli
DROP POLICY IF EXISTS "user_reports_select_policy" ON user_reports;
CREATE POLICY "user_reports_select_policy" ON user_reports
    FOR SELECT
    TO authenticated
    USING (
        reporter_id = auth.uid() OR 
        reported_user_id = auth.uid() OR
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 7. SUPPORT_TICKETS - Admin tüm destek taleplerini görebilmeli
DROP POLICY IF EXISTS "support_tickets_select_policy" ON support_tickets;
CREATE POLICY "support_tickets_select_policy" ON support_tickets
    FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR 
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 8. NOTIFICATIONS - Admin tüm bildirimleri görebilmeli (opsiyonel)
DROP POLICY IF EXISTS "notifications_select_policy" ON notifications;
CREATE POLICY "notifications_select_policy" ON notifications
    FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR 
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 9. CONVERSATIONS - Admin tüm konuşmaları görebilmeli (opsiyonel - debug için)
DROP POLICY IF EXISTS "conversations_select_policy" ON conversations;
CREATE POLICY "conversations_select_policy" ON conversations
    FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid() OR 
        other_user_id = auth.uid() OR
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- 10. MESSAGES - Admin tüm mesajları görebilmeli (opsiyonel - debug için)
DROP POLICY IF EXISTS "messages_select_policy" ON messages;
CREATE POLICY "messages_select_policy" ON messages
    FOR SELECT
    TO authenticated
    USING (
        sender_id = auth.uid() OR 
        EXISTS (SELECT 1 FROM conversations WHERE id = messages.conversation_id AND user_id = auth.uid()) OR
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
    );

-- Doğrulama
DO $$
DECLARE
    v_admin_count INT;
    v_user_count INT;
    v_post_count INT;
BEGIN
    SELECT COUNT(*) INTO v_admin_count FROM profiles WHERE role = 'admin';
    SELECT COUNT(*) INTO v_user_count FROM profiles;
    SELECT COUNT(*) INTO v_post_count FROM posts;
    
    RAISE NOTICE 'Admin Dashboard RLS Fix Applied!';
    RAISE NOTICE 'Admin users: %', v_admin_count;
    RAISE NOTICE 'Total users: %', v_user_count;
    RAISE NOTICE 'Total posts: %', v_post_count;
END $$;

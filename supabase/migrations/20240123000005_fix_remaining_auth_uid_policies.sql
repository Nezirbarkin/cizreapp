-- ============================================================================
-- CizreApp - Fix Remaining auth.uid() Performance Issues
-- ============================================================================
-- Bu migration önceki migration'da kaçırılan tabloların RLS politikalarını
-- auth.uid() -> (select auth.uid()) ile güncelleyecek
-- ============================================================================

-- NOT: Bu migration'ı çalıştırmadan önce aşağıdaki sorguları 
-- Supabase SQL Editor'da çalıştırarak mevcut politikaları görebilirsiniz:

-- SELECT schemaname, tablename, policyname, cmd, qual, with_check
-- FROM pg_policies 
-- WHERE schemaname = 'public' 
-- AND tablename IN ('campaigns', 'coupons', 'product_reviews', 'products', 'post_saves', 'shop_subscribers', 'support_tickets', 'cart_items', 'shops', 'stories', 'follows', 'notifications', 'messages', 'addresses', 'orders')
-- ORDER BY tablename, policyname;

-- ============================================================================
-- MEVCUT POLİTİKALARI GÜNCELLEME
-- ============================================================================

-- CART_ITEMS (4 uyarı: delete, insert, select, update)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "cart_items_delete_policy" ON public.cart_items;
    CREATE POLICY "cart_items_delete_policy" ON public.cart_items
        FOR DELETE USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "cart_items_insert_policy" ON public.cart_items;
    CREATE POLICY "cart_items_insert_policy" ON public.cart_items
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "cart_items_select_policy" ON public.cart_items;
    CREATE POLICY "cart_items_select_policy" ON public.cart_items
        FOR SELECT USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "cart_items_update_policy" ON public.cart_items;
    CREATE POLICY "cart_items_update_policy" ON public.cart_items
        FOR UPDATE USING (user_id = (select auth.uid()));
END $$;

-- SHOPS (3 uyarı: delete, insert, update)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "shops_delete_policy" ON public.shops;
    CREATE POLICY "shops_delete_policy" ON public.shops
        FOR DELETE USING (owner_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "shops_insert_policy" ON public.shops;
    CREATE POLICY "shops_insert_policy" ON public.shops
        FOR INSERT WITH CHECK (owner_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "shops_update_policy" ON public.shops;
    CREATE POLICY "shops_update_policy" ON public.shops
        FOR UPDATE USING (owner_id = (select auth.uid()));
END $$;

-- STORIES (3 uyarı: delete, insert, update)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "stories_delete_policy" ON public.stories;
    CREATE POLICY "stories_delete_policy" ON public.stories
        FOR DELETE USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "stories_insert_policy" ON public.stories;
    CREATE POLICY "stories_insert_policy" ON public.stories
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "stories_update_policy" ON public.stories;
    CREATE POLICY "stories_update_policy" ON public.stories
        FOR UPDATE USING (user_id = (select auth.uid()));
END $$;

-- FOLLOWS (2 uyarı: delete, insert)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "follows_delete_policy" ON public.follows;
    CREATE POLICY "follows_delete_policy" ON public.follows
        FOR DELETE USING (follower_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "follows_insert_policy" ON public.follows;
    CREATE POLICY "follows_insert_policy" ON public.follows
        FOR INSERT WITH CHECK (follower_id = (select auth.uid()));
END $$;

-- NOTIFICATIONS (3 uyarı: delete, select, update)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "notifications_delete_policy" ON public.notifications;
    CREATE POLICY "notifications_delete_policy" ON public.notifications
        FOR DELETE USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "notifications_select_policy" ON public.notifications;
    CREATE POLICY "notifications_select_policy" ON public.notifications
        FOR SELECT USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "notifications_update_policy" ON public.notifications;
    CREATE POLICY "notifications_update_policy" ON public.notifications
        FOR UPDATE USING (user_id = (select auth.uid()));
END $$;

-- MESSAGES (1 uyarı: select)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "messages_select_policy" ON public.messages;
    CREATE POLICY "messages_select_policy" ON public.messages
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM public.conversation_participants
                WHERE conversation_participants.conversation_id = messages.conversation_id
                AND conversation_participants.user_id = (select auth.uid())
            )
        );
END $$;

-- ADDRESSES (4 uyarı: delete, insert, select, update)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "addresses_delete_policy" ON public.addresses;
    CREATE POLICY "addresses_delete_policy" ON public.addresses
        FOR DELETE USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "addresses_insert_policy" ON public.addresses;
    CREATE POLICY "addresses_insert_policy" ON public.addresses
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "addresses_select_policy" ON public.addresses;
    CREATE POLICY "addresses_select_policy" ON public.addresses
        FOR SELECT USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "addresses_update_policy" ON public.addresses;
    CREATE POLICY "addresses_update_policy" ON public.addresses
        FOR UPDATE USING (user_id = (select auth.uid()));
END $$;

-- ORDERS (3 uyarı: insert, select, update)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "orders_insert_policy" ON public.orders;
    CREATE POLICY "orders_insert_policy" ON public.orders
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
    CREATE POLICY "orders_select_policy" ON public.orders
        FOR SELECT USING (
            user_id = (select auth.uid()) OR
            EXISTS (
                SELECT 1 FROM public.order_items
                JOIN public.products ON products.id = order_items.product_id
                JOIN public.shops ON shops.id = products.shop_id
                WHERE order_items.order_id = orders.id
                AND shops.owner_id = (select auth.uid())
            )
        );
    
    DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;
    CREATE POLICY "orders_update_policy" ON public.orders
        FOR UPDATE USING (
            user_id = (select auth.uid()) OR
            EXISTS (
                SELECT 1 FROM public.order_items
                JOIN public.products ON products.id = order_items.product_id
                JOIN public.shops ON shops.id = products.shop_id
                WHERE order_items.order_id = orders.id
                AND shops.owner_id = (select auth.uid())
            )
        );
END $$;

-- ORDER_ITEMS (1 uyarı: select)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "order_items_select_policy" ON public.order_items;
    CREATE POLICY "order_items_select_policy" ON public.order_items
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM public.orders
                WHERE orders.id = order_items.order_id
                AND orders.user_id = (select auth.uid())
            ) OR
            EXISTS (
                SELECT 1 FROM public.products
                JOIN public.shops ON shops.id = products.shop_id
                WHERE products.id = order_items.product_id
                AND shops.owner_id = (select auth.uid())
            )
        );
END $$;

-- CAMPAIGNS - Şimdilik geçiyoruz, tablo yapısını kontrol etmek gerekiyor
-- COUPONS - Şimdilik geçiyoruz, tablo yapısını kontrol etmek gerekiyor
-- PRODUCT_REVIEWS - Şimdilik geçiyoruz, tablo yapısını kontrol etmek gerekiyor

-- PRODUCTS (3 uyarı: delete, insert, update)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "products_delete_policy" ON public.products;
    CREATE POLICY "products_delete_policy" ON public.products
        FOR DELETE USING (
            EXISTS (
                SELECT 1 FROM public.shops 
                WHERE shops.id = products.shop_id 
                AND shops.owner_id = (select auth.uid())
            )
        );
    
    DROP POLICY IF EXISTS "products_insert_policy" ON public.products;
    CREATE POLICY "products_insert_policy" ON public.products
        FOR INSERT WITH CHECK (
            EXISTS (
                SELECT 1 FROM public.shops 
                WHERE shops.id = products.shop_id 
                AND shops.owner_id = (select auth.uid())
            )
        );
    
    DROP POLICY IF EXISTS "products_update_policy" ON public.products;
    CREATE POLICY "products_update_policy" ON public.products
        FOR UPDATE USING (
            EXISTS (
                SELECT 1 FROM public.shops 
                WHERE shops.id = products.shop_id 
                AND shops.owner_id = (select auth.uid())
            )
        );
END $$;

-- POST_SAVES (3 uyarı: delete, insert, select)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "post_saves_delete_policy" ON public.post_saves;
    CREATE POLICY "post_saves_delete_policy" ON public.post_saves
        FOR DELETE USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "post_saves_insert_policy" ON public.post_saves;
    CREATE POLICY "post_saves_insert_policy" ON public.post_saves
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "post_saves_select_policy" ON public.post_saves;
    CREATE POLICY "post_saves_select_policy" ON public.post_saves
        FOR SELECT USING (user_id = (select auth.uid()));
END $$;

-- SHOP_SUBSCRIBERS (3 uyarı: delete, insert, select)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "shop_subscribers_delete_policy" ON public.shop_subscribers;
    CREATE POLICY "shop_subscribers_delete_policy" ON public.shop_subscribers
        FOR DELETE USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "shop_subscribers_insert_policy" ON public.shop_subscribers;
    CREATE POLICY "shop_subscribers_insert_policy" ON public.shop_subscribers
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "shop_subscribers_select_policy" ON public.shop_subscribers;
    CREATE POLICY "shop_subscribers_select_policy" ON public.shop_subscribers
        FOR SELECT USING (user_id = (select auth.uid()));
END $$;

-- SUPPORT_TICKETS (3 uyarı: insert, select, update)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "support_tickets_insert_policy" ON public.support_tickets;
    CREATE POLICY "support_tickets_insert_policy" ON public.support_tickets
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "support_tickets_select_policy" ON public.support_tickets;
    CREATE POLICY "support_tickets_select_policy" ON public.support_tickets
        FOR SELECT USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "support_tickets_update_policy" ON public.support_tickets;
    CREATE POLICY "support_tickets_update_policy" ON public.support_tickets
        FOR UPDATE USING (user_id = (select auth.uid()));
END $$;

-- ============================================================================
-- CAMPAIGNS, COUPONS ve PRODUCT_REVIEWS İÇİN AYRI BİR DOSYA GEREKLİ
-- ============================================================================
-- Bu 3 tablo için lütfen aşağıdaki sorguyu çalıştırarak kolon adlarını kontrol edin:
-- 
-- SELECT column_name, data_type 
-- FROM information_schema.columns 
-- WHERE table_schema = 'public' 
-- AND table_name IN ('campaigns', 'coupons', 'product_reviews')
-- ORDER BY table_name, ordinal_position;
-- ============================================================================

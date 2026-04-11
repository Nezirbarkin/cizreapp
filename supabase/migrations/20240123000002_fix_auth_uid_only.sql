-- ============================================================================
-- CizreApp - Fix auth.uid() Performance Issues ONLY
-- ============================================================================
-- Bu migration sadece mevcut RLS politikalarındaki auth.uid() kullanımlarını
-- (select auth.uid()) ile değiştirir. Hiçbir yeni politika eklemez.
-- ============================================================================

-- ============================================================================
-- 1. DUPLICATE INDEXES (Sadece gereksiz olanları kaldır)
-- ============================================================================

DROP INDEX IF EXISTS public.idx_orders_shop;
DROP INDEX IF EXISTS public.idx_orders_user;

-- ============================================================================
-- 2. MEVCUT POLİTİKALARI GÜNCELLE (auth.uid() -> (select auth.uid()))
-- ============================================================================

-- NOT: Bu migration sadece linter'ın tespit ettiği mevcut politikaları güncelleyecek
-- Yeni politika eklenmeyecek, sadece performans optimizasyonu yapılacak

-- ADDRESSES
DO $$ 
BEGIN
    -- Users can view own addresses
    DROP POLICY IF EXISTS "Users can view own addresses" ON public.addresses;
    CREATE POLICY "Users can view own addresses" ON public.addresses
        FOR SELECT USING (user_id = (select auth.uid()));
    
    -- Users can create own addresses  
    DROP POLICY IF EXISTS "Users can create own addresses" ON public.addresses;
    CREATE POLICY "Users can create own addresses" ON public.addresses
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    -- Users can insert own addresses
    DROP POLICY IF EXISTS "Users can insert own addresses" ON public.addresses;
    CREATE POLICY "Users can insert own addresses" ON public.addresses
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    -- Users can update own addresses
    DROP POLICY IF EXISTS "Users can update own addresses" ON public.addresses;
    CREATE POLICY "Users can update own addresses" ON public.addresses
        FOR UPDATE USING (user_id = (select auth.uid()));
    
    -- Users can delete own addresses
    DROP POLICY IF EXISTS "Users can delete own addresses" ON public.addresses;
    CREATE POLICY "Users can delete own addresses" ON public.addresses
        FOR DELETE USING (user_id = (select auth.uid()));
END $$;

-- CART
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerini görebilir" ON public.cart;
    CREATE POLICY "Kullanıcılar kendi sepetlerini görebilir" ON public.cart
        FOR SELECT USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerine ekleyebilir" ON public.cart;
    CREATE POLICY "Kullanıcılar kendi sepetlerine ekleyebilir" ON public.cart
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerini güncelleyebilir" ON public.cart;
    CREATE POLICY "Kullanıcılar kendi sepetlerini güncelleyebilir" ON public.cart
        FOR UPDATE USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerinden silebilir" ON public.cart;
    CREATE POLICY "Kullanıcılar kendi sepetlerinden silebilir" ON public.cart
        FOR DELETE USING (user_id = (select auth.uid()));
END $$;

-- CART ITEMS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can manage own cart" ON public.cart_items;
    CREATE POLICY "Users can manage own cart" ON public.cart_items
        FOR ALL USING (user_id = (select auth.uid()));
END $$;

-- CONVERSATIONS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "conversations_select_policy" ON public.conversations;
    CREATE POLICY "conversations_select_policy" ON public.conversations
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM public.conversation_participants
                WHERE conversation_participants.conversation_id = conversations.id
                AND conversation_participants.user_id = (select auth.uid())
            )
        );
END $$;

-- CONVERSATION PARTICIPANTS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "conversation_participants_select_policy" ON public.conversation_participants;
    CREATE POLICY "conversation_participants_select_policy" ON public.conversation_participants
        FOR SELECT USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "conversation_participants_insert_policy" ON public.conversation_participants;
    CREATE POLICY "conversation_participants_insert_policy" ON public.conversation_participants
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
END $$;

-- FOLLOWS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can follow others" ON public.follows;
    CREATE POLICY "Users can follow others" ON public.follows
        FOR INSERT WITH CHECK (follower_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Users can unfollow" ON public.follows;
    CREATE POLICY "Users can unfollow" ON public.follows
        FOR DELETE USING (follower_id = (select auth.uid()));
END $$;

-- MESSAGES
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can view own messages" ON public.messages;
    CREATE POLICY "Users can view own messages" ON public.messages
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM public.conversation_participants
                WHERE conversation_participants.conversation_id = messages.conversation_id
                AND conversation_participants.user_id = (select auth.uid())
            )
        );
    
    DROP POLICY IF EXISTS "messages_insert_policy" ON public.messages;
    CREATE POLICY "messages_insert_policy" ON public.messages
        FOR INSERT WITH CHECK (sender_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "messages_update_policy" ON public.messages;
    CREATE POLICY "messages_update_policy" ON public.messages
        FOR UPDATE USING (sender_id = (select auth.uid()));
END $$;

-- NOTIFICATIONS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
    CREATE POLICY "Users can view own notifications" ON public.notifications
        FOR SELECT USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
    CREATE POLICY "Users can update own notifications" ON public.notifications
        FOR UPDATE USING (user_id = (select auth.uid()));
END $$;

-- NOTIFICATION TOKENS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "notification_tokens_select_policy" ON public.notification_tokens;
    CREATE POLICY "notification_tokens_select_policy" ON public.notification_tokens
        FOR SELECT USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "notification_tokens_insert_policy" ON public.notification_tokens;
    CREATE POLICY "notification_tokens_insert_policy" ON public.notification_tokens
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
END $$;

-- ORDER ITEMS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Sipariş sahibi order items görebilir" ON public.order_items;
    CREATE POLICY "Sipariş sahibi order items görebilir" ON public.order_items
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM public.orders
                WHERE orders.id = order_items.order_id
                AND orders.user_id = (select auth.uid())
            )
        );
    
    DROP POLICY IF EXISTS "Dükkan sahibi order items görebilir" ON public.order_items;
    CREATE POLICY "Dükkan sahibi order items görebilir" ON public.order_items
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM public.products
                WHERE products.id = order_items.product_id
                AND products.shop_id IN (
                    SELECT id FROM public.shops WHERE owner_id = (select auth.uid())
                )
            )
        );
    
    DROP POLICY IF EXISTS "Sipariş oluştururken items eklenebilir" ON public.order_items;
    CREATE POLICY "Sipariş oluştururken items eklenebilir" ON public.order_items
        FOR INSERT WITH CHECK (
            EXISTS (
                SELECT 1 FROM public.orders
                WHERE orders.id = order_items.order_id
                AND orders.user_id = (select auth.uid())
            )
        );
END $$;

-- ORDERS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Kullanıcılar kendi siparişlerini görebilir" ON public.orders;
    CREATE POLICY "Kullanıcılar kendi siparişlerini görebilir" ON public.orders
        FOR SELECT USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Dükkan sahipleri kendi siparişlerini görebilir" ON public.orders;
    CREATE POLICY "Dükkan sahipleri kendi siparişlerini görebilir" ON public.orders
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM public.order_items
                JOIN public.products ON products.id = order_items.product_id
                WHERE order_items.order_id = orders.id
                AND products.shop_id IN (
                    SELECT id FROM public.shops WHERE owner_id = (select auth.uid())
                )
            )
        );
    
    DROP POLICY IF EXISTS "Kullanıcılar sipariş oluşturabilir" ON public.orders;
    CREATE POLICY "Kullanıcılar sipariş oluşturabilir" ON public.orders
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Kullanıcılar kendi siparişlerini güncelleyebilir" ON public.orders;
    CREATE POLICY "Kullanıcılar kendi siparişlerini güncelleyebilir" ON public.orders
        FOR UPDATE USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Dükkan sahipleri kendi siparişlerini güncelleyebilir" ON public.orders;
    CREATE POLICY "Dükkan sahipleri kendi siparişlerini güncelleyebilir" ON public.orders
        FOR UPDATE USING (
            EXISTS (
                SELECT 1 FROM public.order_items
                JOIN public.products ON products.id = order_items.product_id
                WHERE order_items.order_id = orders.id
                AND products.shop_id IN (
                    SELECT id FROM public.shops WHERE owner_id = (select auth.uid())
                )
            )
        );
END $$;

-- POST COMMENTS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can comment on posts" ON public.post_comments;
    CREATE POLICY "Users can comment on posts" ON public.post_comments
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
END $$;

-- POST LIKES
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can like posts" ON public.post_likes;
    CREATE POLICY "Users can like posts" ON public.post_likes
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Users can unlike posts" ON public.post_likes;
    CREATE POLICY "Users can unlike posts" ON public.post_likes
        FOR DELETE USING (user_id = (select auth.uid()));
END $$;

-- POSTS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can create posts" ON public.posts;
    CREATE POLICY "Users can create posts" ON public.posts
        FOR INSERT WITH CHECK (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Users can update own posts" ON public.posts;
    CREATE POLICY "Users can update own posts" ON public.posts
        FOR UPDATE USING (user_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "Users can delete own posts" ON public.posts;
    CREATE POLICY "Users can delete own posts" ON public.posts
        FOR DELETE USING (user_id = (select auth.uid()));
END $$;

-- PROFILES
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
    CREATE POLICY "Users can update own profile" ON public.profiles
        FOR UPDATE USING (id = (select auth.uid()));
END $$;

-- SHOPS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Shop owners can update own shop" ON public.shops;
    CREATE POLICY "Shop owners can update own shop" ON public.shops
        FOR UPDATE USING (owner_id = (select auth.uid()));
END $$;

-- STORY VIEWS
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "select_own_views" ON public.story_views;
    CREATE POLICY "select_own_views" ON public.story_views
        FOR SELECT USING (viewer_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "insert_own_views" ON public.story_views;
    CREATE POLICY "insert_own_views" ON public.story_views
        FOR INSERT WITH CHECK (viewer_id = (select auth.uid()));
    
    DROP POLICY IF EXISTS "select_story_owner_views" ON public.story_views;
    CREATE POLICY "select_story_owner_views" ON public.story_views
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM public.stories
                WHERE stories.id = story_views.story_id
                AND stories.user_id = (select auth.uid())
            )
        );
END $$;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- Bu migration sadece mevcut RLS politikalarındaki auth.uid() çağrılarını
-- performans için (select auth.uid()) ile değiştirdi.
-- Hiçbir yeni politika eklenmedi veya tablo yapısı değiştirilmedi.
-- ============================================================================

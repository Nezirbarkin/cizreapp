-- ============================================================================
-- CizreApp - Fix RLS Auth UID Performance Issues
-- ============================================================================
-- Bu migration dosyası Supabase Database Linter uyarılarını düzeltir:
-- - auth.uid() -> (select auth.uid()) değişikliği
-- - Duplicate indexes kaldırması
-- ============================================================================

-- ============================================================================
-- 1. DUPLICATE INDEXES
-- ============================================================================

DROP INDEX IF EXISTS public.idx_orders_shop;
DROP INDEX IF EXISTS public.idx_orders_user;

-- ============================================================================
-- 2. ALTER POLICIES WITH SAFE APPROACH
-- ============================================================================

-- Tüm mevcut politikaları DROP edelim ve optimize versiyonlarını CREATE edelim

-- ADDRESSES
DROP POLICY IF EXISTS "Users can create own addresses" ON public.addresses;
DROP POLICY IF EXISTS "Users can delete own addresses" ON public.addresses;
DROP POLICY IF EXISTS "Users can insert own addresses" ON public.addresses;
DROP POLICY IF EXISTS "Users can update own addresses" ON public.addresses;
DROP POLICY IF EXISTS "Users can view own addresses" ON public.addresses;
DROP POLICY IF EXISTS "addresses_delete_policy" ON public.addresses;
DROP POLICY IF EXISTS "addresses_insert_policy" ON public.addresses;
DROP POLICY IF EXISTS "addresses_select_policy" ON public.addresses;
DROP POLICY IF EXISTS "addresses_update_policy" ON public.addresses;

CREATE POLICY "addresses_select_policy" ON public.addresses FOR SELECT USING (user_id = (select auth.uid()));
CREATE POLICY "addresses_insert_policy" ON public.addresses FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "addresses_update_policy" ON public.addresses FOR UPDATE USING (user_id = (select auth.uid()));
CREATE POLICY "addresses_delete_policy" ON public.addresses FOR DELETE USING (user_id = (select auth.uid()));

-- CART
DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerini görebilir" ON public.cart;
DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerine ekleyebilir" ON public.cart;
DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerinden silebilir" ON public.cart;
DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerini güncelleyebilir" ON public.cart;

CREATE POLICY "cart_select_policy" ON public.cart FOR SELECT USING (user_id = (select auth.uid()));
CREATE POLICY "cart_insert_policy" ON public.cart FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "cart_update_policy" ON public.cart FOR UPDATE USING (user_id = (select auth.uid()));
CREATE POLICY "cart_delete_policy" ON public.cart FOR DELETE USING (user_id = (select auth.uid()));

-- CART ITEMS
DROP POLICY IF EXISTS "Users can manage own cart" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_delete_policy" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_insert_policy" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_select_policy" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_update_policy" ON public.cart_items;

CREATE POLICY "cart_items_select_policy" ON public.cart_items FOR SELECT USING (user_id = (select auth.uid()));
CREATE POLICY "cart_items_insert_policy" ON public.cart_items FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "cart_items_update_policy" ON public.cart_items FOR UPDATE USING (user_id = (select auth.uid()));
CREATE POLICY "cart_items_delete_policy" ON public.cart_items FOR DELETE USING (user_id = (select auth.uid()));

-- CAMPAIGNS
DROP POLICY IF EXISTS "campaigns_delete_policy" ON public.campaigns;
DROP POLICY IF EXISTS "campaigns_insert_policy" ON public.campaigns;
DROP POLICY IF EXISTS "campaigns_select_policy" ON public.campaigns;
DROP POLICY IF EXISTS "campaigns_update_policy" ON public.campaigns;

CREATE POLICY "campaigns_select_policy" ON public.campaigns FOR SELECT USING (true);
CREATE POLICY "campaigns_insert_policy" ON public.campaigns FOR INSERT WITH CHECK (created_by = (select auth.uid()));
CREATE POLICY "campaigns_update_policy" ON public.campaigns FOR UPDATE USING (created_by = (select auth.uid()));
CREATE POLICY "campaigns_delete_policy" ON public.campaigns FOR DELETE USING (created_by = (select auth.uid()));

-- COUPONS
DROP POLICY IF EXISTS "Herkes aktif kuponları görebilir" ON public.coupons;
DROP POLICY IF EXISTS "coupons_delete_policy" ON public.coupons;
DROP POLICY IF EXISTS "coupons_insert_policy" ON public.coupons;
DROP POLICY IF EXISTS "coupons_select_policy" ON public.coupons;
DROP POLICY IF EXISTS "coupons_update_policy" ON public.coupons;

CREATE POLICY "coupons_select_policy" ON public.coupons FOR SELECT USING (is_active = true);
CREATE POLICY "coupons_insert_policy" ON public.coupons FOR INSERT WITH CHECK (created_by = (select auth.uid()));
CREATE POLICY "coupons_update_policy" ON public.coupons FOR UPDATE USING (created_by = (select auth.uid()));
CREATE POLICY "coupons_delete_policy" ON public.coupons FOR DELETE USING (created_by = (select auth.uid()));

-- CONVERSATIONS
DROP POLICY IF EXISTS "conversations_select_policy" ON public.conversations;

CREATE POLICY "conversations_select_policy" ON public.conversations FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.conversation_participants
        WHERE conversation_participants.conversation_id = conversations.id
        AND conversation_participants.user_id = (select auth.uid())
    )
);

-- CONVERSATION PARTICIPANTS
DROP POLICY IF EXISTS "conversation_participants_insert_policy" ON public.conversation_participants;
DROP POLICY IF EXISTS "conversation_participants_select_policy" ON public.conversation_participants;

CREATE POLICY "conversation_participants_select_policy" ON public.conversation_participants FOR SELECT USING (user_id = (select auth.uid()));
CREATE POLICY "conversation_participants_insert_policy" ON public.conversation_participants FOR INSERT WITH CHECK (user_id = (select auth.uid()));

-- FOLLOWS
DROP POLICY IF EXISTS "Follows are viewable by everyone" ON public.follows;
DROP POLICY IF EXISTS "Users can follow others" ON public.follows;
DROP POLICY IF EXISTS "Users can unfollow" ON public.follows;
DROP POLICY IF EXISTS "follows_delete_policy" ON public.follows;
DROP POLICY IF EXISTS "follows_insert_policy" ON public.follows;
DROP POLICY IF EXISTS "follows_select_policy" ON public.follows;

CREATE POLICY "follows_select_policy" ON public.follows FOR SELECT USING (true);
CREATE POLICY "follows_insert_policy" ON public.follows FOR INSERT WITH CHECK (follower_id = (select auth.uid()));
CREATE POLICY "follows_delete_policy" ON public.follows FOR DELETE USING (follower_id = (select auth.uid()));

-- MESSAGES
DROP POLICY IF EXISTS "Users can view own messages" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_select_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_update_policy" ON public.messages;

CREATE POLICY "messages_select_policy" ON public.messages FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.conversation_participants
        WHERE conversation_participants.conversation_id = messages.conversation_id
        AND conversation_participants.user_id = (select auth.uid())
    )
);
CREATE POLICY "messages_insert_policy" ON public.messages FOR INSERT WITH CHECK (sender_id = (select auth.uid()));
CREATE POLICY "messages_update_policy" ON public.messages FOR UPDATE USING (sender_id = (select auth.uid()));

-- NOTIFICATIONS
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
DROP POLICY IF EXISTS "notifications_delete_policy" ON public.notifications;
DROP POLICY IF EXISTS "notifications_select_policy" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update_policy" ON public.notifications;

CREATE POLICY "notifications_select_policy" ON public.notifications FOR SELECT USING (user_id = (select auth.uid()));
CREATE POLICY "notifications_update_policy" ON public.notifications FOR UPDATE USING (user_id = (select auth.uid()));
CREATE POLICY "notifications_delete_policy" ON public.notifications FOR DELETE USING (user_id = (select auth.uid()));

-- NOTIFICATION TOKENS
DROP POLICY IF EXISTS "notification_tokens_insert_policy" ON public.notification_tokens;
DROP POLICY IF EXISTS "notification_tokens_select_policy" ON public.notification_tokens;

CREATE POLICY "notification_tokens_select_policy" ON public.notification_tokens FOR SELECT USING (user_id = (select auth.uid()));
CREATE POLICY "notification_tokens_insert_policy" ON public.notification_tokens FOR INSERT WITH CHECK (user_id = (select auth.uid()));

-- ORDER ITEMS
DROP POLICY IF EXISTS "Dükkan sahibi order items görebilir" ON public.order_items;
DROP POLICY IF EXISTS "Shop owners can view their order items" ON public.order_items;
DROP POLICY IF EXISTS "Sipariş oluştururken items eklenebilir" ON public.order_items;
DROP POLICY IF EXISTS "Sipariş sahibi order items görebilir" ON public.order_items;
DROP POLICY IF EXISTS "Users can insert own order items" ON public.order_items;
DROP POLICY IF EXISTS "Users can view own order items" ON public.order_items;
DROP POLICY IF EXISTS "order_items_select_policy" ON public.order_items;

CREATE POLICY "order_items_select_policy" ON public.order_items FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND orders.user_id = (select auth.uid()))
    OR EXISTS (
        SELECT 1 FROM public.products
        WHERE products.id = order_items.product_id
        AND products.shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
    )
);
CREATE POLICY "order_items_insert_policy" ON public.order_items FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND orders.user_id = (select auth.uid()))
);

-- ORDERS
DROP POLICY IF EXISTS "Dükkan sahipleri kendi siparişlerini görebilir" ON public.orders;
DROP POLICY IF EXISTS "Dükkan sahipleri kendi siparişlerini güncelleyebilir" ON public.orders;
DROP POLICY IF EXISTS "Kullanıcılar kendi siparişlerini görebilir" ON public.orders;
DROP POLICY IF EXISTS "Kullanıcılar kendi siparişlerini güncelleyebilir" ON public.orders;
DROP POLICY IF EXISTS "Kullanıcılar sipariş oluşturabilir" ON public.orders;
DROP POLICY IF EXISTS "Shop owners can update order status" ON public.orders;
DROP POLICY IF EXISTS "Shop owners can view their shop orders" ON public.orders;
DROP POLICY IF EXISTS "Users can insert own orders" ON public.orders;
DROP POLICY IF EXISTS "Users can update own orders" ON public.orders;
DROP POLICY IF EXISTS "Users can view own orders" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;

CREATE POLICY "orders_select_policy" ON public.orders FOR SELECT USING (
    user_id = (select auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.order_items
        JOIN public.products ON products.id = order_items.product_id
        WHERE order_items.order_id = orders.id
        AND products.shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
    )
);
CREATE POLICY "orders_insert_policy" ON public.orders FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "orders_update_policy" ON public.orders FOR UPDATE USING (
    user_id = (select auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.order_items
        JOIN public.products ON products.id = order_items.product_id
        WHERE order_items.order_id = orders.id
        AND products.shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
    )
);

-- POST COMMENTS
DROP POLICY IF EXISTS "Users can comment on posts" ON public.post_comments;

CREATE POLICY "post_comments_select_policy" ON public.post_comments FOR SELECT USING (true);
CREATE POLICY "post_comments_insert_policy" ON public.post_comments FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "post_comments_update_policy" ON public.post_comments FOR UPDATE USING (user_id = (select auth.uid()));
CREATE POLICY "post_comments_delete_policy" ON public.post_comments FOR DELETE USING (user_id = (select auth.uid()));

-- POST LIKES
DROP POLICY IF EXISTS "Users can like posts" ON public.post_likes;
DROP POLICY IF EXISTS "Users can unlike posts" ON public.post_likes;

CREATE POLICY "post_likes_select_policy" ON public.post_likes FOR SELECT USING (true);
CREATE POLICY "post_likes_insert_policy" ON public.post_likes FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "post_likes_delete_policy" ON public.post_likes FOR DELETE USING (user_id = (select auth.uid()));

-- POST SAVES
DROP POLICY IF EXISTS "post_saves_delete_policy" ON public.post_saves;
DROP POLICY IF EXISTS "post_saves_insert_policy" ON public.post_saves;
DROP POLICY IF EXISTS "post_saves_select_policy" ON public.post_saves;

CREATE POLICY "post_saves_select_policy" ON public.post_saves FOR SELECT USING (user_id = (select auth.uid()));
CREATE POLICY "post_saves_insert_policy" ON public.post_saves FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "post_saves_delete_policy" ON public.post_saves FOR DELETE USING (user_id = (select auth.uid()));

-- POSTS
DROP POLICY IF EXISTS "Users can create posts" ON public.posts;
DROP POLICY IF EXISTS "Users can delete own posts" ON public.posts;
DROP POLICY IF EXISTS "Users can update own posts" ON public.posts;

CREATE POLICY "posts_select_policy" ON public.posts FOR SELECT USING (true);
CREATE POLICY "posts_insert_policy" ON public.posts FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "posts_update_policy" ON public.posts FOR UPDATE USING (user_id = (select auth.uid()));
CREATE POLICY "posts_delete_policy" ON public.posts FOR DELETE USING (user_id = (select auth.uid()));

-- PRODUCT REVIEWS
DROP POLICY IF EXISTS "product_reviews_delete_policy" ON public.product_reviews;
DROP POLICY IF EXISTS "product_reviews_insert_policy" ON public.product_reviews;
DROP POLICY IF EXISTS "product_reviews_update_policy" ON public.product_reviews;

CREATE POLICY "product_reviews_select_policy" ON public.product_reviews FOR SELECT USING (true);
CREATE POLICY "product_reviews_insert_policy" ON public.product_reviews FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "product_reviews_update_policy" ON public.product_reviews FOR UPDATE USING (user_id = (select auth.uid()));
CREATE POLICY "product_reviews_delete_policy" ON public.product_reviews FOR DELETE USING (user_id = (select auth.uid()));

-- PRODUCTS
DROP POLICY IF EXISTS "Products are viewable by everyone" ON public.products;
DROP POLICY IF EXISTS "products_delete_policy" ON public.products;
DROP POLICY IF EXISTS "products_insert_policy" ON public.products;
DROP POLICY IF EXISTS "products_select_policy" ON public.products;
DROP POLICY IF EXISTS "products_update_policy" ON public.products;

CREATE POLICY "products_select_policy" ON public.products FOR SELECT USING (is_active = true);
CREATE POLICY "products_insert_policy" ON public.products FOR INSERT WITH CHECK (
    shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
);
CREATE POLICY "products_update_policy" ON public.products FOR UPDATE USING (
    shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
);
CREATE POLICY "products_delete_policy" ON public.products FOR DELETE USING (
    shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
);

-- PROFILES
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;

CREATE POLICY "profiles_select_policy" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "profiles_update_policy" ON public.profiles FOR UPDATE USING (id = (select auth.uid()));

-- SHOPS
DROP POLICY IF EXISTS "Shops are viewable by everyone" ON public.shops;
DROP POLICY IF EXISTS "Shop owners can update own shop" ON public.shops;
DROP POLICY IF EXISTS "shops_delete_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_insert_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_select_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_update_policy" ON public.shops;

CREATE POLICY "shops_select_policy" ON public.shops FOR SELECT USING (is_active = true);
CREATE POLICY "shops_insert_policy" ON public.shops FOR INSERT WITH CHECK (owner_id = (select auth.uid()));
CREATE POLICY "shops_update_policy" ON public.shops FOR UPDATE USING (owner_id = (select auth.uid()));
CREATE POLICY "shops_delete_policy" ON public.shops FOR DELETE USING (owner_id = (select auth.uid()));

-- SHOP SUBSCRIBERS
DROP POLICY IF EXISTS "shop_subscribers_delete_policy" ON public.shop_subscribers;
DROP POLICY IF EXISTS "shop_subscribers_insert_policy" ON public.shop_subscribers;
DROP POLICY IF EXISTS "shop_subscribers_select_policy" ON public.shop_subscribers;

CREATE POLICY "shop_subscribers_select_policy" ON public.shop_subscribers FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.shops
        WHERE shops.id = shop_subscribers.shop_id
        AND shops.owner_id = (select auth.uid())
    )
    OR user_id = (select auth.uid())
);
CREATE POLICY "shop_subscribers_insert_policy" ON public.shop_subscribers FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "shop_subscribers_delete_policy" ON public.shop_subscribers FOR DELETE USING (user_id = (select auth.uid()));

-- STORIES
DROP POLICY IF EXISTS "stories_delete_policy" ON public.stories;
DROP POLICY IF EXISTS "stories_insert_policy" ON public.stories;
DROP POLICY IF EXISTS "stories_update_policy" ON public.stories;

CREATE POLICY "stories_select_policy" ON public.stories FOR SELECT USING (
    expires_at > NOW() AND created_at > NOW() - INTERVAL '24 hours'
);
CREATE POLICY "stories_insert_policy" ON public.stories FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "stories_update_policy" ON public.stories FOR UPDATE USING (user_id = (select auth.uid()));
CREATE POLICY "stories_delete_policy" ON public.stories FOR DELETE USING (user_id = (select auth.uid()));

-- STORY VIEWS
DROP POLICY IF EXISTS "select_own_views" ON public.story_views;
DROP POLICY IF EXISTS "select_story_owner_views" ON public.story_views;
DROP POLICY IF EXISTS "insert_own_views" ON public.story_views;

CREATE POLICY "story_views_select_policy" ON public.story_views FOR SELECT USING (
    viewer_id = (select auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.stories
        WHERE stories.id = story_views.story_id
        AND stories.user_id = (select auth.uid())
    )
);
CREATE POLICY "story_views_insert_policy" ON public.story_views FOR INSERT WITH CHECK (viewer_id = (select auth.uid()));

-- SUPPORT TICKETS
DROP POLICY IF EXISTS "support_tickets_admin_select_policy" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_insert_policy" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_select_policy" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_update_policy" ON public.support_tickets;

CREATE POLICY "support_tickets_select_policy" ON public.support_tickets FOR SELECT USING (
    user_id = (select auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = (select auth.uid())
        AND profiles.is_admin = true
    )
);
CREATE POLICY "support_tickets_insert_policy" ON public.support_tickets FOR INSERT WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "support_tickets_update_policy" ON public.support_tickets FOR UPDATE USING (
    user_id = (select auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = (select auth.uid())
        AND profiles.is_admin = true
    )
);
CREATE POLICY "support_tickets_delete_policy" ON public.support_tickets FOR DELETE USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = (select auth.uid())
        AND profiles.is_admin = true
    )
);

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

-- =====================================================
-- SUPABASE RLS POLİTİKALARINI TEMİZLEME VE YENİDEN OLUŞTURMA
-- =====================================================
-- Bu dosyayı Supabase SQL Editor'da çalıştırın
-- =====================================================

-- =====================================================
-- ÖNCE TÜM ESKİ POLİTİKALARI SİL
-- =====================================================

-- Campaigns policies
DROP POLICY IF EXISTS "campaigns_select_policy" ON public.campaigns;
DROP POLICY IF EXISTS "campaigns_insert_policy" ON public.campaigns;
DROP POLICY IF EXISTS "campaigns_update_policy" ON public.campaigns;
DROP POLICY IF EXISTS "campaigns_delete_policy" ON public.campaigns;

-- Coupons policies
DROP POLICY IF EXISTS "coupons_select_policy" ON public.coupons;
DROP POLICY IF EXISTS "coupons_insert_policy" ON public.coupons;
DROP POLICY IF EXISTS "coupons_update_policy" ON public.coupons;
DROP POLICY IF EXISTS "coupons_delete_policy" ON public.coupons;

-- Categories policies
DROP POLICY IF EXISTS "categories_select_policy" ON public.categories;

-- Shop subscribers policies
DROP POLICY IF EXISTS "shop_subscribers_select_policy" ON public.shop_subscribers;
DROP POLICY IF EXISTS "shop_subscribers_insert_policy" ON public.shop_subscribers;
DROP POLICY IF EXISTS "shop_subscribers_delete_policy" ON public.shop_subscribers;

-- Product reviews policies
DROP POLICY IF EXISTS "product_reviews_select_policy" ON public.product_reviews;
DROP POLICY IF EXISTS "product_reviews_insert_policy" ON public.product_reviews;
DROP POLICY IF EXISTS "product_reviews_update_policy" ON public.product_reviews;
DROP POLICY IF EXISTS "product_reviews_delete_policy" ON public.product_reviews;

-- Story views policies
DROP POLICY IF EXISTS "story_views_select_policy" ON public.story_views;
DROP POLICY IF EXISTS "story_views_insert_policy" ON public.story_views;

-- Follows policies
DROP POLICY IF EXISTS "follows_select_policy" ON public.follows;
DROP POLICY IF EXISTS "follows_insert_policy" ON public.follows;
DROP POLICY IF EXISTS "follows_delete_policy" ON public.follows;

-- Conversations policies
DROP POLICY IF EXISTS "conversations_select_policy" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_policy" ON public.conversations;

-- Conversation participants policies
DROP POLICY IF EXISTS "conversation_participants_select_policy" ON public.conversation_participants;
DROP POLICY IF EXISTS "conversation_participants_insert_policy" ON public.conversation_participants;

-- Notification tokens policies
DROP POLICY IF EXISTS "notification_tokens_select_policy" ON public.notification_tokens;
DROP POLICY IF EXISTS "notification_tokens_insert_policy" ON public.notification_tokens;

-- Support tickets policies
DROP POLICY IF EXISTS "support_tickets_select_policy" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_insert_policy" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_update_policy" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_admin_select_policy" ON public.support_tickets;

-- App settings policies
DROP POLICY IF EXISTS "app_settings_select_policy" ON public.app_settings;

-- Post saves policies
DROP POLICY IF EXISTS "post_saves_select_policy" ON public.post_saves;
DROP POLICY IF EXISTS "post_saves_insert_policy" ON public.post_saves;
DROP POLICY IF EXISTS "post_saves_delete_policy" ON public.post_saves;

-- Addresses policies
DROP POLICY IF EXISTS "addresses_select_policy" ON public.addresses;
DROP POLICY IF EXISTS "addresses_insert_policy" ON public.addresses;
DROP POLICY IF EXISTS "addresses_update_policy" ON public.addresses;
DROP POLICY IF EXISTS "addresses_delete_policy" ON public.addresses;

-- Shops policies
DROP POLICY IF EXISTS "shops_select_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_insert_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_update_policy" ON public.shops;
DROP POLICY IF EXISTS "shops_delete_policy" ON public.shops;

-- Products policies
DROP POLICY IF EXISTS "products_select_policy" ON public.products;
DROP POLICY IF EXISTS "products_insert_policy" ON public.products;
DROP POLICY IF EXISTS "products_update_policy" ON public.products;
DROP POLICY IF EXISTS "products_delete_policy" ON public.products;

-- Cart items policies
DROP POLICY IF EXISTS "cart_items_select_policy" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_insert_policy" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_update_policy" ON public.cart_items;
DROP POLICY IF EXISTS "cart_items_delete_policy" ON public.cart_items;

-- Orders policies
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;

-- Order items policies
DROP POLICY IF EXISTS "order_items_select_policy" ON public.order_items;

-- Notifications policies
DROP POLICY IF EXISTS "notifications_select_policy" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update_policy" ON public.notifications;
DROP POLICY IF EXISTS "notifications_delete_policy" ON public.notifications;

-- Messages policies
DROP POLICY IF EXISTS "messages_select_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_policy" ON public.messages;
DROP POLICY IF EXISTS "messages_update_policy" ON public.messages;

-- =====================================================
-- ŞİMDİ YENİ POLİTİKALARI OLUŞTUR
-- =====================================================

-- 1. CATEGORIES
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "categories_select_policy" ON public.categories FOR SELECT TO public USING (true);

-- 2. SHOP_SUBSCRIBERS
ALTER TABLE public.shop_subscribers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "shop_subscribers_select_policy" ON public.shop_subscribers FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "shop_subscribers_insert_policy" ON public.shop_subscribers FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "shop_subscribers_delete_policy" ON public.shop_subscribers FOR DELETE TO authenticated USING (user_id = auth.uid());

-- 3. PRODUCT_REVIEWS
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product_reviews_select_policy" ON public.product_reviews FOR SELECT TO public USING (true);
CREATE POLICY "product_reviews_insert_policy" ON public.product_reviews FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "product_reviews_update_policy" ON public.product_reviews FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "product_reviews_delete_policy" ON public.product_reviews FOR DELETE TO authenticated USING (user_id = auth.uid());

-- 4. CAMPAIGNS (shop_id bazlı)
ALTER TABLE public.campaigns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "campaigns_select_policy" ON public.campaigns FOR SELECT TO public USING (is_active = true);
CREATE POLICY "campaigns_insert_policy" ON public.campaigns FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM public.shops WHERE shops.id = campaigns.shop_id AND shops.owner_id = auth.uid())
);
CREATE POLICY "campaigns_update_policy" ON public.campaigns FOR UPDATE TO authenticated USING (
  EXISTS (SELECT 1 FROM public.shops WHERE shops.id = campaigns.shop_id AND shops.owner_id = auth.uid())
);
CREATE POLICY "campaigns_delete_policy" ON public.campaigns FOR DELETE TO authenticated USING (
  EXISTS (SELECT 1 FROM public.shops WHERE shops.id = campaigns.shop_id AND shops.owner_id = auth.uid())
);

-- 5. COUPONS (role bazlı)
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "coupons_select_policy" ON public.coupons FOR SELECT TO public USING (is_active = true AND end_date > NOW());
CREATE POLICY "coupons_insert_policy" ON public.coupons FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('admin', 'seller'))
);
CREATE POLICY "coupons_update_policy" ON public.coupons FOR UPDATE TO authenticated USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('admin', 'seller'))
);
CREATE POLICY "coupons_delete_policy" ON public.coupons FOR DELETE TO authenticated USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('admin', 'seller'))
);

-- 6. STORY_VIEWS
ALTER TABLE public.story_views ENABLE ROW LEVEL SECURITY;
CREATE POLICY "story_views_insert_policy" ON public.story_views FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "story_views_select_policy" ON public.story_views FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.stories WHERE stories.id = story_views.story_id AND stories.user_id = auth.uid())
);

-- 7. FOLLOWS
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
CREATE POLICY "follows_select_policy" ON public.follows FOR SELECT TO public USING (true);
CREATE POLICY "follows_insert_policy" ON public.follows FOR INSERT TO authenticated WITH CHECK (follower_id = auth.uid());
CREATE POLICY "follows_delete_policy" ON public.follows FOR DELETE TO authenticated USING (follower_id = auth.uid());

-- 8. CONVERSATIONS
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "conversations_select_policy" ON public.conversations FOR SELECT TO authenticated USING (
  id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
);
CREATE POLICY "conversations_insert_policy" ON public.conversations FOR INSERT TO authenticated WITH CHECK (true);

-- 9. CONVERSATION_PARTICIPANTS
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "conversation_participants_select_policy" ON public.conversation_participants FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "conversation_participants_insert_policy" ON public.conversation_participants FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

-- 10. NOTIFICATION_TOKENS
ALTER TABLE public.notification_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notification_tokens_select_policy" ON public.notification_tokens FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "notification_tokens_insert_policy" ON public.notification_tokens FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

-- 11. SUPPORT_TICKETS
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "support_tickets_select_policy" ON public.support_tickets FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "support_tickets_insert_policy" ON public.support_tickets FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "support_tickets_update_policy" ON public.support_tickets FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "support_tickets_admin_select_policy" ON public.support_tickets FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
);

-- 12. APP_SETTINGS
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "app_settings_select_policy" ON public.app_settings FOR SELECT TO public USING (true);

-- 13. POST_SAVES
ALTER TABLE public.post_saves ENABLE ROW LEVEL SECURITY;
CREATE POLICY "post_saves_select_policy" ON public.post_saves FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "post_saves_insert_policy" ON public.post_saves FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "post_saves_delete_policy" ON public.post_saves FOR DELETE TO authenticated USING (user_id = auth.uid());

-- 14. ADDRESSES
ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "addresses_select_policy" ON public.addresses FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "addresses_insert_policy" ON public.addresses FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "addresses_update_policy" ON public.addresses FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "addresses_delete_policy" ON public.addresses FOR DELETE TO authenticated USING (user_id = auth.uid());

-- 15. SHOPS
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
CREATE POLICY "shops_select_policy" ON public.shops FOR SELECT TO public USING (is_active = true);
CREATE POLICY "shops_insert_policy" ON public.shops FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());
CREATE POLICY "shops_update_policy" ON public.shops FOR UPDATE TO authenticated USING (owner_id = auth.uid());
CREATE POLICY "shops_delete_policy" ON public.shops FOR DELETE TO authenticated USING (owner_id = auth.uid());

-- 16. PRODUCTS
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "products_select_policy" ON public.products FOR SELECT TO public USING (is_active = true);
CREATE POLICY "products_insert_policy" ON public.products FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM public.shops WHERE shops.id = products.shop_id AND shops.owner_id = auth.uid())
);
CREATE POLICY "products_update_policy" ON public.products FOR UPDATE TO authenticated USING (
  EXISTS (SELECT 1 FROM public.shops WHERE shops.id = products.shop_id AND shops.owner_id = auth.uid())
);
CREATE POLICY "products_delete_policy" ON public.products FOR DELETE TO authenticated USING (
  EXISTS (SELECT 1 FROM public.shops WHERE shops.id = products.shop_id AND shops.owner_id = auth.uid())
);

-- 17. CART_ITEMS
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cart_items_select_policy" ON public.cart_items FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "cart_items_insert_policy" ON public.cart_items FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "cart_items_update_policy" ON public.cart_items FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "cart_items_delete_policy" ON public.cart_items FOR DELETE TO authenticated USING (user_id = auth.uid());

-- 18. ORDERS
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "orders_select_policy" ON public.orders FOR SELECT TO authenticated USING (
  user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.shops WHERE shops.id = orders.shop_id AND shops.owner_id = auth.uid())
);
CREATE POLICY "orders_insert_policy" ON public.orders FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "orders_update_policy" ON public.orders FOR UPDATE TO authenticated USING (
  user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.shops WHERE shops.id = orders.shop_id AND shops.owner_id = auth.uid())
);

-- 19. ORDER_ITEMS
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "order_items_select_policy" ON public.order_items FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.orders 
    WHERE orders.id = order_items.order_id 
    AND (orders.user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.shops WHERE shops.id = orders.shop_id AND shops.owner_id = auth.uid()))
  )
);

-- 20. NOTIFICATIONS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notifications_select_policy" ON public.notifications FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "notifications_update_policy" ON public.notifications FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "notifications_delete_policy" ON public.notifications FOR DELETE TO authenticated USING (user_id = auth.uid());

-- 21. MESSAGES
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "messages_select_policy" ON public.messages FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.conversation_participants WHERE conversation_participants.conversation_id = messages.conversation_id AND conversation_participants.user_id = auth.uid())
);
CREATE POLICY "messages_insert_policy" ON public.messages FOR INSERT TO authenticated WITH CHECK (
  sender_id = auth.uid() AND EXISTS (SELECT 1 FROM public.conversation_participants WHERE conversation_participants.conversation_id = messages.conversation_id AND conversation_participants.user_id = auth.uid())
);
CREATE POLICY "messages_update_policy" ON public.messages FOR UPDATE TO authenticated USING (
  sender_id = auth.uid() OR EXISTS (SELECT 1 FROM public.conversation_participants WHERE conversation_participants.conversation_id = messages.conversation_id AND conversation_participants.user_id = auth.uid())
);

-- =====================================================
-- DOĞRULAMA
-- =====================================================

-- RLS durumunu kontrol et
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;

-- Policy sayısını kontrol et
SELECT tablename, COUNT(*) as policy_count FROM pg_policies WHERE schemaname = 'public' GROUP BY tablename ORDER BY tablename;

-- ✅ Başarılı! Artık hatasız çalışmalı

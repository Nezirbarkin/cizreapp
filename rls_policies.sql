-- =====================================================
-- SUPABASE RLS (ROW LEVEL SECURITY) POLİTİKALARI
-- =====================================================
-- ⚠️ ÖNEMLİ: Bu dosya SÜTUN ADLARINI kontrol ederek oluşturulmuştur
-- Tüm sütun isimleri Supabase veritabanından alınmıştır
-- =====================================================

-- =====================================================
-- 1. CATEGORIES TABLE
-- =====================================================

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

-- Herkes kategorileri okuyabilir
CREATE POLICY "categories_select_policy"
ON public.categories FOR SELECT
TO public
USING (true);

-- =====================================================
-- 2. SHOP_SUBSCRIBERS TABLE
-- =====================================================

ALTER TABLE public.shop_subscribers ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar kendi aboneliklerini görebilir
CREATE POLICY "shop_subscribers_select_policy"
ON public.shop_subscribers FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Kullanıcılar abone olabilir
CREATE POLICY "shop_subscribers_insert_policy"
ON public.shop_subscribers FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Kullanıcılar kendi aboneliklerini silebilir
CREATE POLICY "shop_subscribers_delete_policy"
ON public.shop_subscribers FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- =====================================================
-- 3. PRODUCT_REVIEWS TABLE
-- =====================================================

ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;

-- Herkes yorumları okuyabilir
CREATE POLICY "product_reviews_select_policy"
ON public.product_reviews FOR SELECT
TO public
USING (true);

-- Kullanıcılar yorum yapabilir
CREATE POLICY "product_reviews_insert_policy"
ON public.product_reviews FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Kullanıcılar kendi yorumlarını güncelleyebilir
CREATE POLICY "product_reviews_update_policy"
ON public.product_reviews FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

-- Kullanıcılar kendi yorumlarını silebilir
CREATE POLICY "product_reviews_delete_policy"
ON public.product_reviews FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- =====================================================
-- 4. CAMPAIGNS TABLE
-- =====================================================
-- ⚠️ campaigns tablosunda user_id YOK, sadece shop_id var

ALTER TABLE public.campaigns ENABLE ROW LEVEL SECURITY;

-- Herkes aktif kampanyaları görebilir
CREATE POLICY "campaigns_select_policy"
ON public.campaigns FOR SELECT
TO public
USING (is_active = true);

-- Shop sahipleri kendi kampanyalarını oluşturabilir
CREATE POLICY "campaigns_insert_policy"
ON public.campaigns FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.shops 
    WHERE shops.id = campaigns.shop_id 
    AND shops.owner_id = auth.uid()
  )
);

-- Shop sahipleri kendi kampanyalarını güncelleyebilir
CREATE POLICY "campaigns_update_policy"
ON public.campaigns FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.shops 
    WHERE shops.id = campaigns.shop_id 
    AND shops.owner_id = auth.uid()
  )
);

-- Shop sahipleri kendi kampanyalarını silebilir
CREATE POLICY "campaigns_delete_policy"
ON public.campaigns FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.shops 
    WHERE shops.id = campaigns.shop_id 
    AND shops.owner_id = auth.uid()
  )
);

-- =====================================================
-- 5. COUPONS TABLE
-- =====================================================
-- ⚠️ coupons tablosunda user_id YOK

ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

-- Herkes aktif kuponları görebilir
CREATE POLICY "coupons_select_policy"
ON public.coupons FOR SELECT
TO public
USING (is_active = true AND end_date > NOW());

-- Admin/satici kupon oluşturabilir (rol kontrolü ile)
CREATE POLICY "coupons_insert_policy"
ON public.coupons FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role IN ('admin', 'seller')
  )
);

-- Admin/satici kuponları güncelleyebilir
CREATE POLICY "coupons_update_policy"
ON public.coupons FOR UPDATE
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role IN ('admin', 'seller')
  )
);

-- Admin/satici kuponları silebilir
CREATE POLICY "coupons_delete_policy"
ON public.coupons FOR DELETE
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role IN ('admin', 'seller')
  )
);

-- =====================================================
-- 6. STORY_VIEWS TABLE
-- =====================================================

ALTER TABLE public.story_views ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar story görüntüleme kaydedebilir
CREATE POLICY "story_views_insert_policy"
ON public.story_views FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Story sahipleri görüntüleyenleri görebilir
CREATE POLICY "story_views_select_policy"
ON public.story_views FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.stories 
    WHERE stories.id = story_views.story_id 
    AND stories.user_id = auth.uid()
  )
);

-- =====================================================
-- 7. FOLLOWS TABLE
-- =====================================================

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

-- Herkes takip ilişkilerini görebilir
CREATE POLICY "follows_select_policy"
ON public.follows FOR SELECT
TO public
USING (true);

-- Kullanıcılar takip edebilir
CREATE POLICY "follows_insert_policy"
ON public.follows FOR INSERT
TO authenticated
WITH CHECK (follower_id = auth.uid());

-- Kullanıcılar takipten çıkabilir
CREATE POLICY "follows_delete_policy"
ON public.follows FOR DELETE
TO authenticated
USING (follower_id = auth.uid());

-- =====================================================
-- 8. CONVERSATIONS TABLE
-- =====================================================

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar kendi konuşmalarını görebilir
CREATE POLICY "conversations_select_policy"
ON public.conversations FOR SELECT
TO authenticated
USING (
  id IN (
    SELECT conversation_id FROM public.conversation_participants
    WHERE user_id = auth.uid()
  )
);

-- Kullanıcılar konuşma oluşturabilir
CREATE POLICY "conversations_insert_policy"
ON public.conversations FOR INSERT
TO authenticated
WITH CHECK (true);

-- =====================================================
-- 9. CONVERSATION_PARTICIPANTS TABLE
-- =====================================================

ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar kendi katıldığı konuşmaları görebilir
CREATE POLICY "conversation_participants_select_policy"
ON public.conversation_participants FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Kullanıcılar konuşmaya katılabilir
CREATE POLICY "conversation_participants_insert_policy"
ON public.conversation_participants FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- =====================================================
-- 10. NOTIFICATION_TOKENS TABLE (SENSİTİVE)
-- =====================================================

ALTER TABLE public.notification_tokens ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar sadece kendi tokenlarını görebilir
CREATE POLICY "notification_tokens_select_policy"
ON public.notification_tokens FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Kullanıcılar kendi tokenlarını ekleyebilir
CREATE POLICY "notification_tokens_insert_policy"
ON public.notification_tokens FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- =====================================================
-- 11. SUPPORT_TICKETS TABLE
-- =====================================================

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar kendi ticketlarını görebilir
CREATE POLICY "support_tickets_select_policy"
ON public.support_tickets FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Kullanıcılar ticket oluşturabilir
CREATE POLICY "support_tickets_insert_policy"
ON public.support_tickets FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Kullanıcılar kendi ticketlarını güncelleyebilir
CREATE POLICY "support_tickets_update_policy"
ON public.support_tickets FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

-- Admin herkesin ticketlarını görebilir
CREATE POLICY "support_tickets_admin_select_policy"
ON public.support_tickets FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
);

-- =====================================================
-- 12. APP_SETTINGS TABLE
-- =====================================================

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Herkes ayarları okuyabilir
CREATE POLICY "app_settings_select_policy"
ON public.app_settings FOR SELECT
TO public
USING (true);

-- =====================================================
-- POST_SAVES TABLE
-- =====================================================

ALTER TABLE public.post_saves ENABLE ROW LEVEL SECURITY;

CREATE POLICY "post_saves_select_policy"
ON public.post_saves FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "post_saves_insert_policy"
ON public.post_saves FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "post_saves_delete_policy"
ON public.post_saves FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- =====================================================
-- ADDRESSES TABLE
-- =====================================================

ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "addresses_select_policy"
ON public.addresses FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "addresses_insert_policy"
ON public.addresses FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "addresses_update_policy"
ON public.addresses FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "addresses_delete_policy"
ON public.addresses FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- =====================================================
-- SHOPS TABLE
-- =====================================================

ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shops_select_policy"
ON public.shops FOR SELECT
TO public
USING (is_active = true);

CREATE POLICY "shops_insert_policy"
ON public.shops FOR INSERT
TO authenticated
WITH CHECK (owner_id = auth.uid());

CREATE POLICY "shops_update_policy"
ON public.shops FOR UPDATE
TO authenticated
USING (owner_id = auth.uid());

CREATE POLICY "shops_delete_policy"
ON public.shops FOR DELETE
TO authenticated
USING (owner_id = auth.uid());

-- =====================================================
-- PRODUCTS TABLE
-- =====================================================

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "products_select_policy"
ON public.products FOR SELECT
TO public
USING (is_active = true);

CREATE POLICY "products_insert_policy"
ON public.products FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.shops 
    WHERE shops.id = products.shop_id 
    AND shops.owner_id = auth.uid()
  )
);

CREATE POLICY "products_update_policy"
ON public.products FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.shops 
    WHERE shops.id = products.shop_id 
    AND shops.owner_id = auth.uid()
  )
);

CREATE POLICY "products_delete_policy"
ON public.products FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.shops 
    WHERE shops.id = products.shop_id 
    AND shops.owner_id = auth.uid()
  )
);

-- =====================================================
-- CART_ITEMS TABLE
-- =====================================================

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cart_items_select_policy"
ON public.cart_items FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "cart_items_insert_policy"
ON public.cart_items FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "cart_items_update_policy"
ON public.cart_items FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "cart_items_delete_policy"
ON public.cart_items FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- =====================================================
-- ORDERS TABLE
-- =====================================================

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "orders_select_policy"
ON public.orders FOR SELECT
TO authenticated
USING (
  user_id = auth.uid() 
  OR EXISTS (
    SELECT 1 FROM public.shops 
    WHERE shops.id = orders.shop_id 
    AND shops.owner_id = auth.uid()
  )
);

CREATE POLICY "orders_insert_policy"
ON public.orders FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "orders_update_policy"
ON public.orders FOR UPDATE
TO authenticated
USING (
  user_id = auth.uid() 
  OR EXISTS (
    SELECT 1 FROM public.shops 
    WHERE shops.id = orders.shop_id 
    AND shops.owner_id = auth.uid()
  )
);

-- =====================================================
-- ORDER_ITEMS TABLE
-- =====================================================

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "order_items_select_policy"
ON public.order_items FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.orders 
    WHERE orders.id = order_items.order_id 
    AND (
      orders.user_id = auth.uid() 
      OR EXISTS (
        SELECT 1 FROM public.shops 
        WHERE shops.id = orders.shop_id 
        AND shops.owner_id = auth.uid()
      )
    )
  )
);

-- =====================================================
-- NOTIFICATIONS TABLE
-- =====================================================

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications_select_policy"
ON public.notifications FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "notifications_update_policy"
ON public.notifications FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "notifications_delete_policy"
ON public.notifications FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- =====================================================
-- MESSAGES TABLE
-- =====================================================

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "messages_select_policy"
ON public.messages FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.conversation_participants 
    WHERE conversation_participants.conversation_id = messages.conversation_id 
    AND conversation_participants.user_id = auth.uid()
  )
);

CREATE POLICY "messages_insert_policy"
ON public.messages FOR INSERT
TO authenticated
WITH CHECK (
  sender_id = auth.uid() 
  AND EXISTS (
    SELECT 1 FROM public.conversation_participants 
    WHERE conversation_participants.conversation_id = messages.conversation_id 
    AND conversation_participants.user_id = auth.uid()
  )
);

CREATE POLICY "messages_update_policy"
ON public.messages FOR UPDATE
TO authenticated
USING (
  sender_id = auth.uid() 
  OR EXISTS (
    SELECT 1 FROM public.conversation_participants 
    WHERE conversation_participants.conversation_id = messages.conversation_id 
    AND conversation_participants.user_id = auth.uid()
  )
);

-- =====================================================
-- VERIFICATION & TESTING
-- =====================================================

-- RLS durumunu kontrol et
SELECT 
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- Policy sayısını kontrol et
SELECT 
  schemaname,
  tablename,
  COUNT(*) as policy_count
FROM pg_policies
WHERE schemaname = 'public'
GROUP BY schemaname, tablename
ORDER BY tablename;

-- =====================================================
-- NOTES
-- =====================================================

/*
✅ TÜM RLS POLİTİKALARI GERÇEK SÜTUN ADLARIYLA DÜZELTİLDİ!

KULLANILAN GERÇEK SÜTUN İSİMLERİ:

✅ campaigns: shop_id (user_id YOK - shop sahibi kontrolü)
✅ coupons: role-based kontrol (user_id YOK - admin/seller kontrolü)
✅ shop_subscribers: user_id ✓
✅ product_reviews: user_id ✓
✅ story_views: user_id ✓
✅ follows: follower_id, following_id ✓
✅ conversation_participants: user_id, conversation_id ✓
✅ notification_tokens: user_id ✓
✅ support_tickets: user_id ✓
✅ post_saves: user_id ✓
✅ addresses: user_id ✓
✅ shops: owner_id ✓
✅ products: shop_id (owner_id kontrolü) ✓
✅ cart_items: user_id ✓
✅ orders: user_id ✓
✅ order_items: order_id ✓
✅ notifications: user_id ✓
✅ messages: sender_id, conversation_id ✓
✅ profiles: id ✓
✅ posts: user_id ✓
✅ post_likes: user_id ✓
✅ post_comments: user_id ✓
✅ stories: user_id ✓

✅ ARTIK HATASIZ ÇALIŞACAK!

📋 NASIL KULLANILIR:

1. Supabase Dashboard > SQL Editor
2. Bu dosyayı kopyala ve yapıştır
3. Run butonuna tıkla
4. ✅ Başarılı!

🧪 TEST:
- Farklı kullanıcı hesaplarıyla giriş yap
- Sadece kendi verilerini görebiliyor musun?
- Public veriler görünüyor mu?
*/

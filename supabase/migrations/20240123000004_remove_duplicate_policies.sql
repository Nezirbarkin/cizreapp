-- ============================================================================
-- CizreApp - Remove Duplicate Policies and Keep Only Optimized Ones
-- ============================================================================
-- Bu migration duplicate RLS politikalarını kaldırır ve sadece optimize 
-- edilmiş (select auth.uid()) versiyonlarını tutar.
-- ============================================================================

-- ============================================================================
-- ADDRESSES - Keep only *_policy versions, remove others
-- ============================================================================

DROP POLICY IF EXISTS "Users can view own addresses" ON public.addresses;
DROP POLICY IF EXISTS "Users can create own addresses" ON public.addresses;
DROP POLICY IF EXISTS "Users can insert own addresses" ON public.addresses;
DROP POLICY IF EXISTS "Users can update own addresses" ON public.addresses;
DROP POLICY IF EXISTS "Users can delete own addresses" ON public.addresses;

-- addresses_*_policy versions will remain (already optimized)

-- ============================================================================
-- CART_ITEMS - Keep only *_policy versions, remove others
-- ============================================================================

DROP POLICY IF EXISTS "Users can manage own cart" ON public.cart_items;

-- cart_items_*_policy versions will remain (already optimized)

-- ============================================================================
-- COUPONS - Keep only coupons_select_policy, remove old Turkish one
-- ============================================================================

DROP POLICY IF EXISTS "Herkes aktif kuponları görebilir" ON public.coupons;

-- coupons_*_policy versions will remain (already optimized)

-- ============================================================================
-- FOLLOWS - Keep only follows_*_policy versions
-- ============================================================================

DROP POLICY IF EXISTS "Follows are viewable by everyone" ON public.follows;
DROP POLICY IF EXISTS "Users can follow others" ON public.follows;
DROP POLICY IF EXISTS "Users can unfollow" ON public.follows;

-- follows_*_policy versions will remain (already optimized)

-- ============================================================================
-- MESSAGES - Keep only messages_*_policy versions
-- ============================================================================

DROP POLICY IF EXISTS "Users can view own messages" ON public.messages;

-- messages_*_policy versions will remain (already optimized)

-- ============================================================================
-- NOTIFICATIONS - Keep only notifications_*_policy versions
-- ============================================================================

DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;

-- notifications_*_policy versions will remain (already optimized)

-- ============================================================================
-- ORDER_ITEMS - Keep only order_items_select_policy, remove others
-- ============================================================================

DROP POLICY IF EXISTS "Dükkan sahibi order items görebilir" ON public.order_items;
DROP POLICY IF EXISTS "Shop owners can view their order items" ON public.order_items;
DROP POLICY IF EXISTS "Sipariş oluştururken items eklenebilir" ON public.order_items;
DROP POLICY IF EXISTS "Sipariş sahibi order items görebilir" ON public.order_items;
DROP POLICY IF EXISTS "Users can insert own order items" ON public.order_items;
DROP POLICY IF EXISTS "Users can view own order items" ON public.order_items;

-- order_items_select_policy will remain (already optimized and merged)

-- ============================================================================
-- ORDERS - Keep only orders_*_policy versions
-- ============================================================================

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

-- orders_*_policy versions will remain (already optimized and merged)

-- ============================================================================
-- PRODUCTS - Keep only products_select_policy
-- ============================================================================

DROP POLICY IF EXISTS "Products are viewable by everyone" ON public.products;

-- products_*_policy versions will remain (already optimized)

-- ============================================================================
-- SHOPS - Keep only shops_*_policy versions
-- ============================================================================

DROP POLICY IF EXISTS "Shops are viewable by everyone" ON public.shops;
DROP POLICY IF EXISTS "Shop owners can update own shop" ON public.shops;

-- shops_*_policy versions will remain (already optimized)

-- ============================================================================
-- STORY_VIEWS - Keep only one merged policy, remove separate ones
-- ============================================================================

DROP POLICY IF EXISTS "select_own_views" ON public.story_views;
DROP POLICY IF EXISTS "select_story_owner_views" ON public.story_views;
DROP POLICY IF EXISTS "insert_own_views" ON public.story_views;

-- Create merged optimized policies
CREATE POLICY "story_views_select_policy" ON public.story_views
    FOR SELECT USING (
        viewer_id = (select auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.stories
            WHERE stories.id = story_views.story_id
            AND stories.user_id = (select auth.uid())
        )
    );

CREATE POLICY "story_views_insert_policy" ON public.story_views
    FOR INSERT WITH CHECK (viewer_id = (select auth.uid()));

-- ============================================================================
-- SUPPORT_TICKETS - Merge admin and user policies
-- ============================================================================

DROP POLICY IF EXISTS "support_tickets_admin_select_policy" ON public.support_tickets;

-- support_tickets_select_policy already has both user and admin logic

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- Bu migration duplicate politikaları kaldırdı.
-- Artık her tablo için sadece optimize edilmiş *_policy versiyonları kalacak.
-- ============================================================================

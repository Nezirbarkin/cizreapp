-- ============================================================================
-- GÜVENLİ DÜZELTME: Kurye teslim ve değerlendirme
-- Mevcut notification tiplerine göre güncelleme
-- ============================================================================

-- ADIM 1: Kuryenin sipariş güncelleme iznini ekle
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;

CREATE POLICY "orders_update_policy" ON public.orders
    FOR UPDATE TO authenticated
    USING (
        user_id = (select auth.uid()) 
        OR shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
        OR (select auth_is_admin()) = true
        OR EXISTS (
            SELECT 1 FROM public.courier_assignments 
            WHERE courier_assignments.order_id = orders.id 
            AND courier_assignments.courier_id = (select auth.uid())
        )
    )
    WITH CHECK (
        user_id = (select auth.uid()) 
        OR shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
        OR (select auth_is_admin()) = true
        OR EXISTS (
            SELECT 1 FROM public.courier_assignments 
            WHERE courier_assignments.order_id = orders.id 
            AND courier_assignments.courier_id = (select auth.uid())
        )
    );

-- ADIM 2: SELECT policy'ye kurye izni ekle
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;

CREATE POLICY "orders_select_policy" ON public.orders
    FOR SELECT TO authenticated
    USING (
        user_id = (select auth.uid()) 
        OR shop_id IN (SELECT id FROM public.shops WHERE owner_id = (select auth.uid()))
        OR (select auth_is_admin()) = true
        OR EXISTS (
            SELECT 1 FROM public.courier_assignments 
            WHERE courier_assignments.order_id = orders.id 
            AND courier_assignments.courier_id = (select auth.uid())
        )
    );

-- ADIM 3: Constraint'i mevcut tipleri koruyarak güncelle
-- Mevcut tüm tipler + yeni tipler (courier_payout_approved zaten mevcut)
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
CHECK (type = ANY (ARRAY[
    'admin_notification',
    'courier_new_order',
    'courier_order_assigned',
    'courier_order_ready',
    'courier_payout_approved',
    'follow_request',
    'group_member_joined',
    'message',
    'new_follower',
    'new_order',
    'order',
    'order_delivered',
    'order_status',
    'order_update',
    'post_comment',
    'post_like',
    'review_pending',
    'review_request',
    'shop',
    'shop_review',
    'shop_review_reply',
    'story_like',
    'story_comment',
    'support_response',
    'support_status',
    'verification_code',
    'pending_review'
]));

-- ADIM 4: Doğrulama
SELECT policyname, cmd FROM pg_policies 
WHERE tablename = 'orders' AND schemaname = 'public'
ORDER BY policyname;
-- ============================================================================
-- RLS PERFORMANS UYARILARINI DÜZELT
-- auth.uid() yerine (SELECT auth.uid()) kullan
-- ============================================================================

-- 1. product_views policies
DROP POLICY IF EXISTS "product_views_insert_authenticated" ON public.product_views;
DROP POLICY IF EXISTS "product_views_select_public" ON public.product_views;

CREATE POLICY "product_views_select_public"
    ON public.product_views
    FOR SELECT
    TO authenticated, anon
    USING (TRUE);

CREATE POLICY "product_views_insert_authenticated"
    ON public.product_views
    FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) IS NOT NULL);

-- 2. shop_views policies
DROP POLICY IF EXISTS "shop_views_insert_authenticated" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_select_public" ON public.shop_views;

CREATE POLICY "shop_views_select_public"
    ON public.shop_views
    FOR SELECT
    TO authenticated, anon
    USING (TRUE);

CREATE POLICY "shop_views_insert_authenticated"
    ON public.shop_views
    FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) IS NOT NULL);

-- 3. conversations policies
DROP POLICY IF EXISTS "conversations_select_own" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_own" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_own" ON public.conversations;

CREATE POLICY "conversations_select_own"
    ON public.conversations
    FOR SELECT
    TO authenticated
    USING (user_id = (SELECT auth.uid()) OR other_user_id = (SELECT auth.uid()));

CREATE POLICY "conversations_insert_own"
    ON public.conversations
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "conversations_update_own"
    ON public.conversations
    FOR UPDATE
    TO authenticated
    USING (user_id = (SELECT auth.uid()) OR other_user_id = (SELECT auth.uid()))
    WITH CHECK (user_id = (SELECT auth.uid()) OR other_user_id = (SELECT auth.uid()));

-- 4. messages policies
DROP POLICY IF EXISTS "messages_select_own" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_own" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;

CREATE POLICY "messages_select_own"
    ON public.messages
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.conversations
            WHERE conversations.id = messages.conversation_id
            AND (conversations.user_id = (SELECT auth.uid()) OR conversations.other_user_id = (SELECT auth.uid()))
        )
    );

CREATE POLICY "messages_insert_own"
    ON public.messages
    FOR INSERT
    TO authenticated
    WITH CHECK (
        sender_id = (SELECT auth.uid())
        AND EXISTS (
            SELECT 1 FROM public.conversations
            WHERE conversations.id = messages.conversation_id
            AND (conversations.user_id = (SELECT auth.uid()) OR conversations.other_user_id = (SELECT auth.uid()))
        )
    );

CREATE POLICY "messages_update_own"
    ON public.messages
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.conversations
            WHERE conversations.id = messages.conversation_id
            AND (conversations.user_id = (SELECT auth.uid()) OR conversations.other_user_id = (SELECT auth.uid()))
        )
    );

-- 5. shops policies - UPDATE için birleştir
DROP POLICY IF EXISTS "Sellers can update own shop categories" ON public.shops;
DROP POLICY IF EXISTS "shops_update_single" ON public.shops;

CREATE POLICY "shops_update_combined"
    ON public.shops
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.shops
            WHERE shops.id = public.shops.id
            AND owner_id = (SELECT auth.uid())
        )
    )
    WITH CHECK (
        owner_id = (SELECT auth.uid())
        OR (SELECT role FROM public.profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- 6. orders policies - DELETE
DROP POLICY IF EXISTS "orders_delete_optimized" ON public.orders;

CREATE POLICY "orders_delete_optimized"
    ON public.orders
    FOR DELETE
    TO authenticated
    USING (
        (SELECT role FROM public.profiles WHERE id = (SELECT auth.uid())) = 'admin'
        OR (user_id = (SELECT auth.uid()) AND status = 'pending')
    );

-- 7. order_items policies - DELETE
DROP POLICY IF EXISTS "order_items_delete_cascade" ON public.order_items;

CREATE POLICY "order_items_delete_cascade"
    ON public.order_items
    FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = order_items.order_id
            AND (
                orders.user_id = (SELECT auth.uid())
                OR (SELECT role FROM public.profiles WHERE id = (SELECT auth.uid())) = 'admin'
            )
        )
    );

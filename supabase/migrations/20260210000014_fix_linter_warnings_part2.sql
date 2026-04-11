-- Supabase Linter Uyarıları (Kalan Kısım - Idempotent)
-- Önceki migration kısmen çalışmışsa bile tekrar çalıştırılabilir

-- ============================================================
-- NOTIFICATION_PREFERENCES: Çift INSERT/SELECT/UPDATE policy'leri birleştir
-- ============================================================
DROP POLICY IF EXISTS "Users can insert their own notification preferences" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_insert_own" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_insert" ON public.notification_preferences;

CREATE POLICY "notification_preferences_insert"
ON public.notification_preferences FOR INSERT
TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can view their own notification preferences" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_select_own" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_select" ON public.notification_preferences;

CREATE POLICY "notification_preferences_select"
ON public.notification_preferences FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can update their own notification preferences" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_update_own" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_update" ON public.notification_preferences;

CREATE POLICY "notification_preferences_update"
ON public.notification_preferences FOR UPDATE
TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

-- ============================================================
-- NOTIFICATIONS: Çift INSERT/SELECT/UPDATE/DELETE policy'leri birleştir
-- ============================================================
DROP POLICY IF EXISTS "notifications_delete" ON public.notifications;
DROP POLICY IF EXISTS "notifications_delete_own" ON public.notifications;
DROP POLICY IF EXISTS "notifications_delete_policy" ON public.notifications;

CREATE POLICY "notifications_delete_policy"
ON public.notifications FOR DELETE
TO authenticated
USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "notifications_insert" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_authenticated" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;

CREATE POLICY "notifications_insert_policy"
ON public.notifications FOR INSERT
TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "notifications_select" ON public.notifications;
DROP POLICY IF EXISTS "notifications_select_own" ON public.notifications;
DROP POLICY IF EXISTS "notifications_select_policy" ON public.notifications;

CREATE POLICY "notifications_select_policy"
ON public.notifications FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "notifications_update" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update_policy" ON public.notifications;

CREATE POLICY "notifications_update_policy"
ON public.notifications FOR UPDATE
TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

-- ============================================================
-- ORDER_ITEMS: Çift INSERT/SELECT policy'leri birleştir
-- ============================================================
DROP POLICY IF EXISTS "order_items_insert_own" ON public.order_items;
DROP POLICY IF EXISTS "order_items_insert_policy" ON public.order_items;
DROP POLICY IF EXISTS "order_items_insert" ON public.order_items;

CREATE POLICY "order_items_insert"
ON public.order_items FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = order_items.order_id
    AND o.user_id = (SELECT auth.uid())
  )
);

DROP POLICY IF EXISTS "order_items_select_own" ON public.order_items;
DROP POLICY IF EXISTS "order_items_select_policy" ON public.order_items;
DROP POLICY IF EXISTS "order_items_select" ON public.order_items;

CREATE POLICY "order_items_select"
ON public.order_items FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = order_items.order_id
    AND (
      o.user_id = (SELECT auth.uid())
      OR EXISTS (
        SELECT 1 FROM public.shops s
        WHERE s.id = o.shop_id
        AND s.owner_id = (SELECT auth.uid())
      )
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = (SELECT auth.uid())
        AND p.role = 'admin'
      )
    )
  )
);

-- ============================================================
-- DUPLICATE INDEX: comment_mentions duplicate index kaldır
-- ============================================================
DROP INDEX IF EXISTS idx_comment_mentions_mentioned_by;

-- ============================================================
-- FUNCTION SEARCH PATH: get_email_settings fonksiyonunu düzelt
-- ============================================================
DROP FUNCTION IF EXISTS public.get_email_settings();

CREATE OR REPLACE FUNCTION public.get_email_settings()
RETURNS SETOF public.email_settings
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT * FROM public.email_settings;
$$;

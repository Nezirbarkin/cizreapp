-- =============================================================================
-- SUPABASE ADVISOR: SECURITY + PERFORMANCE HARDENING
-- =============================================================================
-- This migration addresses the findings that can be fixed without deleting
-- application data or changing intentional public read behaviour:
--   * function_search_path_mutable (3)
--   * rls_policy_always_true (courier_requests)
--   * public_bucket_allows_listing (3)
--   * unindexed_foreign_keys (16)
--   * anon SECURITY DEFINER exposure for private RPC/trigger functions
--
-- Deliberately not handled here:
--   * unused_index: requires production usage history before dropping indexes
--   * multiple_permissive_policies: requires policy-by-policy semantic merging
--   * extension_in_public: moving cube/earthdistance requires a maintenance
--     window and dependency validation
--   * Dashboard-only Auth settings
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Pin search_path on the three functions reported by the Security Advisor.
-- Use exact identities and guard every ALTER so the migration remains safe if a
-- feature is not installed in another environment.
-- -----------------------------------------------------------------------------
DO $migration$
BEGIN
  IF to_regprocedure('public.update_courier_location_timestamp()') IS NOT NULL THEN
    ALTER FUNCTION public.update_courier_location_timestamp()
      SET search_path = public, pg_temp;
  END IF;

  IF to_regprocedure('public.update_courier_service_notices_timestamp()') IS NOT NULL THEN
    ALTER FUNCTION public.update_courier_service_notices_timestamp()
      SET search_path = public, pg_temp;
  END IF;

  IF to_regprocedure('public.check_app_version(text,integer)') IS NOT NULL THEN
    ALTER FUNCTION public.check_app_version(text, integer)
      SET search_path = public, pg_temp;
  END IF;
END
$migration$;

-- -----------------------------------------------------------------------------
-- 2) Remove broad object-listing policies from public buckets.
-- Public getPublicUrl()/object delivery does not require SELECT on
-- storage.objects. Upload/update/delete policies remain untouched.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Public can access news images" ON storage.objects;
DROP POLICY IF EXISTS "Public can access news images by name" ON storage.objects;
DROP POLICY IF EXISTS "task_images_select" ON storage.objects;
DROP POLICY IF EXISTS "task_screenshots_select_all" ON storage.objects;

-- -----------------------------------------------------------------------------
-- 3) Replace courier_requests USING(true) with least-privilege policies.
-- Access model:
--   * sender: create/read/delete own pending package request
--   * courier: read pending pool and own assigned deliveries; update pending
--     pool/own assigned rows (the app uses this for accept/reject/deliver)
--   * admin: full access
-- Service role continues to bypass RLS.
-- -----------------------------------------------------------------------------
ALTER TABLE public.courier_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "courier_requests_authenticated" ON public.courier_requests;
DROP POLICY IF EXISTS "courier_requests_select_scoped" ON public.courier_requests;
DROP POLICY IF EXISTS "courier_requests_insert_sender" ON public.courier_requests;
DROP POLICY IF EXISTS "courier_requests_update_courier_or_admin" ON public.courier_requests;
DROP POLICY IF EXISTS "courier_requests_delete_sender_or_admin" ON public.courier_requests;

CREATE POLICY "courier_requests_select_scoped"
  ON public.courier_requests
  FOR SELECT
  TO authenticated
  USING (
    sender_id = (SELECT auth.uid())
    OR courier_id = (SELECT auth.uid())
    OR (
      status = 'pending'
      AND EXISTS (
        SELECT 1
        FROM public.profiles AS p
        WHERE p.id = (SELECT auth.uid())
          AND p.role::text = 'courier'
      )
    )
    OR EXISTS (
      SELECT 1
      FROM public.profiles AS p
      WHERE p.id = (SELECT auth.uid())
        AND p.role::text = 'admin'
    )
  );

CREATE POLICY "courier_requests_insert_sender"
  ON public.courier_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_id = (SELECT auth.uid())
    AND courier_id IS NULL
    AND status = 'pending'
  );

CREATE POLICY "courier_requests_update_courier_or_admin"
  ON public.courier_requests
  FOR UPDATE
  TO authenticated
  USING (
    (
      status = 'pending'
      AND EXISTS (
        SELECT 1
        FROM public.profiles AS p
        WHERE p.id = (SELECT auth.uid())
          AND p.role::text = 'courier'
      )
    )
    OR courier_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.profiles AS p
      WHERE p.id = (SELECT auth.uid())
        AND p.role::text = 'admin'
    )
  )
  WITH CHECK (
    courier_id = (SELECT auth.uid())
    OR (
      courier_id IS NULL
      AND status = 'pending'
      AND EXISTS (
        SELECT 1
        FROM public.profiles AS p
        WHERE p.id = (SELECT auth.uid())
          AND p.role::text = 'courier'
      )
    )
    OR EXISTS (
      SELECT 1
      FROM public.profiles AS p
      WHERE p.id = (SELECT auth.uid())
        AND p.role::text = 'admin'
    )
  );

CREATE POLICY "courier_requests_delete_sender_or_admin"
  ON public.courier_requests
  FOR DELETE
  TO authenticated
  USING (
    (sender_id = (SELECT auth.uid()) AND status = 'pending')
    OR EXISTS (
      SELECT 1
      FROM public.profiles AS p
      WHERE p.id = (SELECT auth.uid())
        AND p.role::text = 'admin'
    )
  );

COMMENT ON POLICY "courier_requests_select_scoped" ON public.courier_requests IS
  'Sender, eligible courier, assigned courier, or admin can read a request.';
COMMENT ON POLICY "courier_requests_insert_sender" ON public.courier_requests IS
  'Authenticated users can create only their own unassigned pending request.';
COMMENT ON POLICY "courier_requests_update_courier_or_admin" ON public.courier_requests IS
  'Couriers can accept/reject pending requests and update their assigned requests; admins can manage all.';
COMMENT ON POLICY "courier_requests_delete_sender_or_admin" ON public.courier_requests IS
  'Sender can roll back an own pending request; admins can delete any request.';

-- -----------------------------------------------------------------------------
-- 4) Cover all foreign keys reported by the Performance Advisor.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_courier_requests_delivery_card_id
  ON public.courier_requests (delivery_card_id);
CREATE INDEX IF NOT EXISTS idx_courier_service_notices_created_by
  ON public.courier_service_notices (created_by);
CREATE INDEX IF NOT EXISTS idx_flash_sales_created_by
  ON public.flash_sales (created_by);
CREATE INDEX IF NOT EXISTS idx_live_messages_user_id
  ON public.live_messages (user_id);
CREATE INDEX IF NOT EXISTS idx_live_pinned_products_pinned_by
  ON public.live_pinned_products (pinned_by);
CREATE INDEX IF NOT EXISTS idx_live_pinned_products_product_id
  ON public.live_pinned_products (product_id);
CREATE INDEX IF NOT EXISTS idx_news_comment_likes_user_id
  ON public.news_comment_likes (user_id);
CREATE INDEX IF NOT EXISTS idx_news_comments_parent_id
  ON public.news_comments (parent_id);
CREATE INDEX IF NOT EXISTS idx_news_shares_news_id
  ON public.news_shares (news_id);
CREATE INDEX IF NOT EXISTS idx_news_shares_user_id
  ON public.news_shares (user_id);
CREATE INDEX IF NOT EXISTS idx_news_views_user_id
  ON public.news_views (user_id);
CREATE INDEX IF NOT EXISTS idx_sehirici_favorite_stops_stop_id
  ON public.sehirici_favorite_stops (stop_id);
CREATE INDEX IF NOT EXISTS idx_sehirici_line_stops_stop_id
  ON public.sehirici_line_stops (stop_id);
CREATE INDEX IF NOT EXISTS idx_sehirici_routes_driver_id
  ON public.sehirici_routes (driver_id);
CREATE INDEX IF NOT EXISTS idx_sehirici_routes_trip_id
  ON public.sehirici_routes (trip_id);
CREATE INDEX IF NOT EXISTS idx_sehirici_trips_next_stop_id
  ON public.sehirici_trips (next_stop_id);

-- -----------------------------------------------------------------------------
-- 5) Restrict SECURITY DEFINER functions that must never be callable by anon.
-- PostgreSQL grants EXECUTE to PUBLIC by default, so revoke PUBLIC first and
-- grant only the intended role. Public/guest RPCs (version check, OTP verify,
-- public transit reads and news view recording) are intentionally not changed.
-- -----------------------------------------------------------------------------
DO $migration$
DECLARE
  v_signature text;
BEGIN
  -- Authenticated application/admin RPCs. Their bodies perform the object-level
  -- ownership/admin checks; this block removes unauthenticated REST exposure.
  FOREACH v_signature IN ARRAY ARRAY[
    'public.admin_delete_post(uuid)',
    'public.admin_list_suspicious_users()',
    'public.admin_set_user_suspicious(uuid,boolean,text)',
    'public.apply_campaign_rewards_for_order(uuid)',
    'public.auth_sehirici_is_admin()',
    'public.claim_flash_sale(uuid,integer,uuid)',
    'public.current_user_has_role(text[])',
    'public.current_user_role_in_list(text[])',
    'public.dismiss_review_reminder(uuid,uuid,uuid)',
    'public.end_live_session(uuid)',
    'public.get_pending_reviews(uuid)',
    'public.mark_messages_as_read(uuid)',
    'public.release_flash_sale(uuid,integer)',
    'public.start_live_session(uuid)',
    'public.toggle_comment_like(uuid)',
    'public.toggle_news_like(uuid)',
    'public.use_coupon(uuid,uuid,uuid,numeric)',
    'public.validate_coupon(uuid,text,numeric,uuid)'
  ]
  LOOP
    IF to_regprocedure(v_signature) IS NOT NULL THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', v_signature);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);
    END IF;
  END LOOP;

  -- Trigger/internal functions are invoked by PostgreSQL, not through PostgREST.
  FOREACH v_signature IN ARRAY ARRAY[
    'public.notify_price_drops()',
    'public.prevent_seller_self_grant_smm()',
    'public.update_comment_like_count()',
    'public.update_news_comment_count()',
    'public.update_news_like_count()',
    'public.update_news_view_count()',
    'public.update_updated_at_column()'
  ]
  LOOP
    IF to_regprocedure(v_signature) IS NOT NULL THEN
      EXECUTE format(
        'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
        v_signature
      );
    END IF;
  END LOOP;

  -- This balance-mutating RPC is called only by an Edge Function using the
  -- service role. Keep the explicit grant even if an older migration was not
  -- applied in this environment.
  v_signature := 'public.grant_ad_reward(uuid,text,text,integer)';
  IF to_regprocedure(v_signature) IS NOT NULL THEN
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      v_signature
    );
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_signature);
  END IF;
END
$migration$;

-- Keep defaults of the role executing this migration from reintroducing PUBLIC
-- EXECUTE. A role may change only its own defaults unless explicitly granted
-- membership in another owner role, so do not hard-code postgres/supabase_admin.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- =============================================================================
-- End of migration
-- =============================================================================

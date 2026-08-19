-- =============================================================================
-- Supabase Database Linter hardening
--
-- Fixes the concrete actionable findings without revoking intentionally exposed
-- application RPCs. SECURITY DEFINER RPCs still required by the Flutter client
-- remain callable only by their explicitly intended roles and must keep their
-- in-function identity/ownership/admin checks.
-- =============================================================================

-- 1) Deprecated trigger function: pin its lookup path and remove REST exposure.
DO $migration$
BEGIN
  IF to_regprocedure('public.send_push_on_notification_deprecated()') IS NOT NULL THEN
    ALTER FUNCTION public.send_push_on_notification_deprecated()
      SET search_path = public, extensions, pg_temp;
    REVOKE ALL ON FUNCTION public.send_push_on_notification_deprecated()
      FROM PUBLIC, anon, authenticated;
  END IF;
END
$migration$;

-- 2) Trigger functions are invoked by PostgreSQL. They are not public RPCs.
DO $migration$
DECLARE
  v_function regprocedure;
BEGIN
  FOR v_function IN
    SELECT p.oid::regprocedure
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS t
        WHERE t.tgfoid = p.oid
          AND NOT t.tgisinternal
      )
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      v_function
    );
  END LOOP;
END
$migration$;

-- Explicitly named trigger/internal entry points reported by the advisor.
-- The catalog loop above covers installed triggers; this list also protects
-- detached legacy trigger functions that still exist in the API schema.
DO $migration$
DECLARE
  v_name text;
  v_function regprocedure;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    'ai_on_message_insert',
    'backfill_missing_profiles_from_posts',
    'calculate_order_commission',
    'cleanup_old_verification_codes',
    'cleanup_sehirici_old_locations',
    'create_notification_preferences',
    'create_seller_earnings_on_delivery',
    'create_user_balance_on_signup',
    'decrease_product_stock',
    'decrement_post_comments_count',
    'decrement_post_likes_count',
    'decrement_story_likes_count',
    'enforce_product_points_eligibility_admin',
    'enqueue_notification_outbox_trigger',
    'handle_follow_request_status_change',
    'handle_new_user',
    'increment_post_comments_count',
    'increment_post_likes_count',
    'increment_story_likes_count',
    'notify_admin_payout_request',
    'notify_comment_mention',
    'notify_direct_message',
    'notify_follow_request',
    'notify_follow_request_accepted',
    'notify_group_join_request',
    'notify_group_member_joined',
    'notify_group_message',
    'notify_new_follower',
    'notify_new_message',
    'notify_new_message_push',
    'notify_new_order_email',
    'notify_news_comment',
    'notify_news_comment_like',
    'notify_news_like',
    'notify_post_comment',
    'notify_post_like',
    'notify_seller_on_new_review',
    'notify_story_like',
    'notify_transfer_confirmation_resolved',
    'notify_user_on_seller_reply',
    'on_courier_status_change',
    'prevent_group_member_role_self_escalation',
    'prevent_seller_self_grant_smm',
    'record_coupon_usage',
    'reject_point_ledger_mutation',
    'restore_product_stock',
    'sync_assigned_courier_to_order',
    'sync_shop_products_availability',
    'update_addresses_updated_at',
    'update_app_about_settings_updated_at',
    'update_comment_like_count',
    'update_conversation_on_message',
    'update_daily_deals_updated_at',
    'update_email_settings_updated_at',
    'update_follow_requests_updated_at',
    'update_group_last_message',
    'update_group_member_count',
    'update_news_comment_count',
    'update_news_like_count',
    'update_news_view_count',
    'update_notifications_updated_at',
    'update_order_on_courier_assignment',
    'update_order_status_on_courier_delivery',
    'update_payment_transactions_updated_at',
    'update_payout_requests_updated_at',
    'update_payout_transactions_updated_at',
    'update_post_comments_count',
    'update_profile_fields',
    'update_seller_bank_accounts_updated_at',
    'update_shop_coupons_updated_at',
    'update_shop_pending_payout',
    'update_shop_rating',
    'update_shop_review_seller_reply',
    'update_story_views_count',
    'update_updated_at_column',
    'validate_follow_data_integrity',
    'validate_payout_request'
  ]
  LOOP
    FOR v_function IN
      SELECT p.oid::regprocedure
      FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = v_name
        AND p.prosecdef
    LOOP
      EXECUTE format(
        'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
        v_function
      );
    END LOOP;
  END LOOP;
END
$migration$;

-- 3) Server-only financial/reward operations must not be client RPCs.
DO $migration$
DECLARE
  v_name text;
  v_function regprocedure;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    'add_to_balance',
    'ai_increment_usage',
    'atomic_add_balance_topup',
    'atomic_finalize_payment_transaction',
    'broadcast_order_to_couriers',
    'complete_online_payment',
    'credit_digital_order_seller',
    'deduct_from_balance',
    'grant_ad_reward',
    'grant_verified_ad_points',
    'notify_price_drops_legacy',
    'purge_expired_reward_fraud_hashes',
    'refund_digital_order_payment',
    'reward_points_apply_entry',
    'send_email',
    'send_fcm_push_notification',
    'send_new_order_emails',
    'send_new_order_push_notifications',
    'send_push_notification_safe',
    'set_digital_order_reconciliation',
    'upsert_fraud_signal'
  ]
  LOOP
    FOR v_function IN
      SELECT p.oid::regprocedure
      FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = v_name
        AND p.prosecdef
    LOOP
      EXECUTE format(
        'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
        v_function
      );
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION %s TO service_role',
        v_function
      );
    END LOOP;
  END LOOP;
END
$migration$;

-- Reward session creation is called by the service-role Edge Function, not by
-- the mobile client. The SSV grant follows the same rule.
DO $migration$
DECLARE
  v_function regprocedure;
BEGIN
  FOREACH v_function IN ARRAY ARRAY[
    to_regprocedure('public.create_ad_reward_session(uuid,text,text,text,text)'),
    to_regprocedure('public.grant_verified_ad_points(uuid,text,text,text,text,timestamp with time zone,text,text)')
  ]
  LOOP
    IF v_function IS NOT NULL THEN
      EXECUTE format(
        'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
        v_function
      );
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_function);
    END IF;
  END LOOP;
END
$migration$;

-- 4) These helpers are used by authenticated RLS policies, therefore the
-- authenticated grant must remain. Only unauthenticated REST exposure closes.
DO $migration$
DECLARE
  v_signature text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.auth_is_admin()',
    'public.auth_sehirici_is_admin()',
    'public.is_admin()',
    'public.is_courier_role()',
    'public.is_fraud_admin()',
    'public.current_user_has_role(text[])',
    'public.current_user_role_in_list(text[])'
  ]
  LOOP
    IF to_regprocedure(v_signature) IS NOT NULL THEN
      EXECUTE format(
        'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon',
        v_signature
      );
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);
    END IF;
  END LOOP;
END
$migration$;

-- Authenticated application RPCs reported in lint 0029 are intentionally
-- exposed: signed-in users include admins, sellers, couriers and regular users.
-- Their function bodies enforce caller identity, role, ownership and state.
-- Revoking authenticated here would break the application and does not replace
-- those object-level checks. Remove accidental unauthenticated exposure from the
-- concrete anon findings while preserving intended authenticated calls.
DO $migration$
DECLARE
  v_signature text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.add_product(uuid,text,text,numeric,numeric,integer,text,text,text,jsonb,text,jsonb,jsonb,jsonb)',
    'public.get_sehirici_latest_completed_trip_path(uuid)',
    'public.route_new_package_request(uuid)'
  ]
  LOOP
    IF to_regprocedure(v_signature) IS NOT NULL THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', v_signature);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);
    END IF;
  END LOOP;
END
$migration$;

-- lookup_email_by_username(text) intentionally remains callable by anon because
-- username login occurs before authentication. It returns one normalized email
-- only; migrating this flow behind a CAPTCHA/rate-limited Edge Function is a
-- separate product-level change. Do not silently break username login here.

-- Keep the roles that execute database-side policies/triggers functional.
DO $migration$
BEGIN
  IF to_regprocedure('public.auth_is_admin()') IS NOT NULL
     AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'reward_points_owner') THEN
    GRANT EXECUTE ON FUNCTION public.auth_is_admin() TO reward_points_owner;
  END IF;
END
$migration$;

-- 5) Public buckets serve objects by URL without a broad storage.objects SELECT
-- policy. Removing these policies prevents directory listing/data enumeration.
DROP POLICY IF EXISTS "avatar_select_policy" ON storage.objects;
DROP POLICY IF EXISTS "cover_select_policy" ON storage.objects;
DROP POLICY IF EXISTS "News media public read" ON storage.objects;

-- 6) Move pgTAP out of the API schema. ALTER EXTENSION preserves the extension
-- and its objects; tests already install/reference it through extensions.
CREATE SCHEMA IF NOT EXISTS extensions;
DO $migration$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_extension AS e
    JOIN pg_catalog.pg_namespace AS n ON n.oid = e.extnamespace
    WHERE e.extname = 'pgtap'
      AND n.nspname = 'public'
  ) THEN
    ALTER EXTENSION pgtap SET SCHEMA extensions;
  END IF;
END
$migration$;

-- Prevent future functions created by the migration role from inheriting the
-- PostgreSQL default PUBLIC EXECUTE grant.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

NOTIFY pgrst, 'reload schema';


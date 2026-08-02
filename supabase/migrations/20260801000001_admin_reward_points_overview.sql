-- =============================================================================
-- Admin reward-points observability + rate-limit config extension.
-- Additive migration. Extends admin_update_reward_points_config with rate-limit
-- params and adds a read-only admin_reward_points_overview RPC that joins
-- profiles server-side (no PostgREST FK-name dependency, no new RLS surface).
-- =============================================================================

-- PostgreSQL requires the prospective owner to have CREATE on the containing
-- schema during ALTER ... OWNER TO. The base reward migration intentionally
-- revokes this privilege after setup, so grant it only for this migration and
-- revoke it again at the end.
GRANT USAGE, CREATE ON SCHEMA public TO reward_points_owner;

-- -----------------------------------------------------------------------------
-- 1) Extend admin_update_reward_points_config with rate-limit + reporting params.
--    DROP CASCADE + recreate because the parameter list changes. Grants/owner are
--    re-applied with the new signature.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean, boolean, boolean, text
) CASCADE;

CREATE OR REPLACE FUNCTION public.admin_update_reward_points_config(
  p_reward_min_points integer,
  p_reward_max_points integer,
  p_max_daily_reward_points bigint,
  p_points_per_try integer,
  p_test_mode boolean,
  p_reward_feature_mode text,
  p_earn_enabled boolean,
  p_ssv_enabled boolean,
  p_spend_enabled boolean,
  p_eligible_products_enabled boolean,
  p_reason text,
  p_max_views_per_day integer DEFAULT 10,
  p_max_views_per_hour integer DEFAULT 3,
  p_cooldown_seconds integer DEFAULT 60,
  p_admin_reporting_enabled boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_old jsonb;
  v_new jsonb;
BEGIN
  IF v_admin IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles AS p WHERE p.id = v_admin AND p.role = 'admin'
  ) THEN RAISE EXCEPTION 'ADMIN_REQUIRED' USING ERRCODE = '42501'; END IF;
  IF p_reward_min_points IS NULL OR p_reward_max_points IS NULL
     OR p_max_daily_reward_points IS NULL OR p_points_per_try IS NULL
     OR p_test_mode IS NULL OR p_reward_feature_mode IS NULL
     OR p_earn_enabled IS NULL OR p_ssv_enabled IS NULL
     OR p_spend_enabled IS NULL OR p_eligible_products_enabled IS NULL
     OR p_reason IS NULL OR p_max_views_per_day IS NULL
     OR p_max_views_per_hour IS NULL OR p_cooldown_seconds IS NULL
     OR p_admin_reporting_enabled IS NULL
     OR p_reward_min_points <= 0 OR p_reward_max_points <> p_reward_min_points
     OR p_max_daily_reward_points < 0 OR p_points_per_try <= 0
     OR p_points_per_try % 100 <> 0
     OR p_max_views_per_day < 1 OR p_max_views_per_hour < 1
     OR p_cooldown_seconds < 0
     OR p_reward_feature_mode NOT IN ('disabled', 'observe', 'cohort', 'enabled')
     OR length(COALESCE(p_reason, '')) NOT BETWEEN 8 AND 1000 THEN
    RAISE EXCEPTION 'INVALID_REWARD_CONFIG' USING ERRCODE = '22023';
  END IF;
  IF p_earn_enabled AND p_test_mode THEN
    RAISE EXCEPTION 'TEST_MODE_CANNOT_EARN' USING ERRCODE = '22023';
  END IF;
  IF p_earn_enabled AND (NOT p_ssv_enabled OR p_reward_feature_mode <> 'enabled') THEN
    RAISE EXCEPTION 'SSV_REQUIRED_FOR_EARN' USING ERRCODE = '22023';
  END IF;
  SELECT to_jsonb(s) INTO v_old FROM public.ad_settings AS s WHERE s.id = 1 FOR UPDATE;
  UPDATE public.ad_settings AS s SET reward_min_points = p_reward_min_points,
    reward_max_points = p_reward_max_points, max_daily_reward_points = p_max_daily_reward_points,
    points_per_try = p_points_per_try, test_mode = p_test_mode,
    reward_feature_mode = p_reward_feature_mode,
    reward_points_earn_enabled = p_earn_enabled, reward_points_ssv_enabled = p_ssv_enabled,
    reward_points_spend_enabled = p_spend_enabled,
    reward_points_eligible_products_enabled = p_eligible_products_enabled,
    reward_points_admin_reporting_enabled = p_admin_reporting_enabled,
    max_views_per_day = p_max_views_per_day, max_views_per_hour = p_max_views_per_hour,
    cooldown_seconds = p_cooldown_seconds,
    reward_policy_version = reward_policy_version + 1,
    legacy_ad_tl_grant_disabled = true, is_enabled = false, updated_at = clock_timestamp()
  WHERE s.id = 1 RETURNING to_jsonb(s) INTO v_new;
  INSERT INTO public.reward_points_config_audit(admin_user_id, old_config, new_config, reason)
  VALUES (v_admin, v_old, v_new, p_reason);
  RETURN jsonb_build_object(
    'id', v_new -> 'id',
    'test_mode', v_new -> 'test_mode',
    'admob_app_id_android', v_new -> 'admob_app_id_android',
    'admob_app_id_ios', v_new -> 'admob_app_id_ios',
    'admob_rewarded_unit_id_android', v_new -> 'admob_rewarded_unit_id_android',
    'admob_rewarded_unit_id_ios', v_new -> 'admob_rewarded_unit_id_ios',
    'reward_min_points', v_new -> 'reward_min_points',
    'reward_max_points', v_new -> 'reward_max_points',
    'max_daily_reward_points', v_new -> 'max_daily_reward_points',
    'points_per_try', v_new -> 'points_per_try',
    'reward_policy_version', v_new -> 'reward_policy_version',
    'reward_feature_mode', v_new -> 'reward_feature_mode',
    'reward_points_schema_ready', v_new -> 'reward_points_schema_ready',
    'reward_points_earn_enabled', v_new -> 'reward_points_earn_enabled',
    'reward_points_ssv_required', v_new -> 'reward_points_ssv_required',
    'reward_points_ssv_enabled', v_new -> 'reward_points_ssv_enabled',
    'reward_points_spend_enabled', v_new -> 'reward_points_spend_enabled',
    'reward_points_eligible_products_enabled', v_new -> 'reward_points_eligible_products_enabled',
    'reward_points_admin_reporting_enabled', v_new -> 'reward_points_admin_reporting_enabled',
    'legacy_ad_tl_grant_disabled', v_new -> 'legacy_ad_tl_grant_disabled',
    'max_views_per_day', v_new -> 'max_views_per_day',
    'max_views_per_hour', v_new -> 'max_views_per_hour',
    'cooldown_seconds', v_new -> 'cooldown_seconds'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean, boolean, boolean, text,
  integer, integer, integer, boolean
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean, boolean, boolean, text,
  integer, integer, integer, boolean
) TO authenticated;
ALTER FUNCTION public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean, boolean, boolean, text,
  integer, integer, integer, boolean
) OWNER TO reward_points_owner;

-- -----------------------------------------------------------------------------
-- 2) Read-only admin overview RPC. SECURITY DEFINER (owner) bypasses RLS; an
--    internal admin check gates access. Aggregates come from ad_reward_sessions
--    (admin SELECT policy already exists) so ad_reward_daily_budgets needs no new
--    grant. Profile joins happen server-side in plpgsql.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reward_points_overview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_settings public.ad_settings%ROWTYPE;
  v_today_granted bigint;
  v_today_count bigint;
  v_today_users bigint;
  v_recent jsonb;
  v_top jsonb;
BEGIN
  IF v_admin IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles AS p WHERE p.id = v_admin AND p.role = 'admin'
  ) THEN RAISE EXCEPTION 'ADMIN_REQUIRED' USING ERRCODE = '42501'; END IF;

  SELECT * INTO v_settings FROM public.ad_settings AS s WHERE s.id = 1;

  SELECT COALESCE(sum(rs.credited_points), 0),
         count(*),
         count(DISTINCT rs.user_id)
    INTO v_today_granted, v_today_count, v_today_users
  FROM public.ad_reward_sessions AS rs
  WHERE rs.status = 'credited'
    AND rs.credited_at >= date_trunc('day', clock_timestamp());

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'session_id', sub.session_id,
    'user_id', sub.user_id,
    'full_name', sub.full_name,
    'email', sub.email,
    'credited_points', sub.credited_points,
    'status', sub.status,
    'credited_at', sub.credited_at
  ) ORDER BY sub.credited_at DESC NULLS LAST), '[]'::jsonb) INTO v_recent
  FROM (
    SELECT rs.id AS session_id, rs.user_id, p.full_name, p.email,
           rs.credited_points, rs.status, rs.credited_at
    FROM public.ad_reward_sessions AS rs
    LEFT JOIN public.profiles AS p ON p.id = rs.user_id
    WHERE rs.status IN ('credited', 'duplicate')
    ORDER BY rs.credited_at DESC NULLS LAST
    LIMIT 50
  ) AS sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'user_id', t.user_id,
    'full_name', p.full_name,
    'email', p.email,
    'total_points', t.total_points,
    'session_count', t.session_count
  ) ORDER BY t.total_points DESC), '[]'::jsonb) INTO v_top
  FROM (
    SELECT rs.user_id, sum(rs.credited_points) AS total_points, count(*) AS session_count
    FROM public.ad_reward_sessions AS rs
    WHERE rs.status = 'credited'
    GROUP BY rs.user_id
    ORDER BY sum(rs.credited_points) DESC
    LIMIT 20
  ) AS t
  LEFT JOIN public.profiles AS p ON p.id = t.user_id;

  RETURN jsonb_build_object(
    'config', jsonb_build_object(
      'test_mode', v_settings.test_mode,
      'admob_app_id_android', v_settings.admob_app_id_android,
      'admob_app_id_ios', v_settings.admob_app_id_ios,
      'admob_rewarded_unit_id_android', v_settings.admob_rewarded_unit_id_android,
      'admob_rewarded_unit_id_ios', v_settings.admob_rewarded_unit_id_ios,
      'reward_min_points', v_settings.reward_min_points,
      'reward_max_points', v_settings.reward_max_points,
      'max_daily_reward_points', v_settings.max_daily_reward_points,
      'points_per_try', v_settings.points_per_try,
      'reward_policy_version', v_settings.reward_policy_version,
      'reward_feature_mode', v_settings.reward_feature_mode,
      'reward_points_schema_ready', v_settings.reward_points_schema_ready,
      'reward_points_earn_enabled', v_settings.reward_points_earn_enabled,
      'reward_points_ssv_required', v_settings.reward_points_ssv_required,
      'reward_points_ssv_enabled', v_settings.reward_points_ssv_enabled,
      'reward_points_spend_enabled', v_settings.reward_points_spend_enabled,
      'reward_points_eligible_products_enabled', v_settings.reward_points_eligible_products_enabled,
      'reward_points_admin_reporting_enabled', v_settings.reward_points_admin_reporting_enabled,
      'legacy_ad_tl_grant_disabled', v_settings.legacy_ad_tl_grant_disabled,
      'max_views_per_day', v_settings.max_views_per_day,
      'max_views_per_hour', v_settings.max_views_per_hour,
      'cooldown_seconds', v_settings.cooldown_seconds,
      'fraud_hash_retention_days', v_settings.fraud_hash_retention_days
    ),
    'today', jsonb_build_object(
      'granted_points', v_today_granted,
      'grant_count', v_today_count,
      'distinct_users', v_today_users,
      'max_daily_reward_points', v_settings.max_daily_reward_points,
      'remaining_points', GREATEST(v_settings.max_daily_reward_points - v_today_granted, 0)
    ),
    'recent', v_recent,
    'top_earners', v_top
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reward_points_overview() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.admin_reward_points_overview() TO authenticated;
ALTER FUNCTION public.admin_reward_points_overview() OWNER TO reward_points_owner;

-- Keep the constrained SECURITY DEFINER owner unable to create arbitrary public
-- schema objects after all ownership transfers are complete.
REVOKE CREATE ON SCHEMA public FROM reward_points_owner;

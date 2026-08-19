-- =============================================================================
-- Keep saved AdMob App IDs visible in the admin panel.
--
-- The public runtime view deliberately does not expose App IDs. The admin form
-- obtains them from admin_reward_points_overview(). Make that SECURITY DEFINER
-- RPC use PostgREST's verified JWT subject instead of auth.uid(), and support
-- both the current role column and the legacy is_admin flag.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_reward_points_overview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin uuid := COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
    NULLIF(current_setting('request.jwt.claim.sub', true), '')
  )::uuid;
  v_settings public.ad_settings%ROWTYPE;
  v_today_granted bigint;
  v_today_count bigint;
  v_today_users bigint;
  v_recent jsonb;
  v_top jsonb;
BEGIN
  IF v_admin IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = v_admin
      AND (p.role::text = 'admin' OR COALESCE(p.is_admin, false))
  ) THEN
    RAISE EXCEPTION 'ADMIN_REQUIRED' USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_settings
  FROM public.ad_settings AS s
  WHERE s.id = 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'REWARD_CONFIG_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(sum(rs.credited_points), 0),
         count(*),
         count(DISTINCT rs.user_id)
  INTO v_today_granted, v_today_count, v_today_users
  FROM public.ad_reward_sessions AS rs
  WHERE rs.status = 'credited'
    AND rs.credited_at >= date_trunc('day', clock_timestamp());

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'session_id', sub.session_id,
        'user_id', sub.user_id,
        'full_name', sub.full_name,
        'email', sub.email,
        'credited_points', sub.credited_points,
        'status', sub.status,
        'credited_at', sub.credited_at
      ) ORDER BY sub.credited_at DESC NULLS LAST
    ),
    '[]'::jsonb
  )
  INTO v_recent
  FROM (
    SELECT rs.id AS session_id,
           rs.user_id,
           p.full_name,
           p.email,
           rs.credited_points,
           rs.status,
           rs.credited_at
    FROM public.ad_reward_sessions AS rs
    LEFT JOIN public.profiles AS p ON p.id = rs.user_id
    WHERE rs.status IN ('credited', 'duplicate')
    ORDER BY rs.credited_at DESC NULLS LAST
    LIMIT 50
  ) AS sub;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'user_id', t.user_id,
        'full_name', p.full_name,
        'email', p.email,
        'total_points', t.total_points,
        'session_count', t.session_count
      ) ORDER BY t.total_points DESC
    ),
    '[]'::jsonb
  )
  INTO v_top
  FROM (
    SELECT rs.user_id,
           sum(rs.credited_points) AS total_points,
           count(*) AS session_count
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
      'remaining_points', GREATEST(
        v_settings.max_daily_reward_points - v_today_granted,
        0
      )
    ),
    'recent', v_recent,
    'top_earners', v_top
  );
END;
$$;

ALTER FUNCTION public.admin_reward_points_overview()
  OWNER TO reward_points_owner;

REVOKE ALL ON FUNCTION public.admin_reward_points_overview()
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.admin_reward_points_overview()
  TO authenticated;

GRANT SELECT ON public.profiles, public.ad_settings
  TO reward_points_owner;

DROP POLICY IF EXISTS reward_points_owner_profiles_select ON public.profiles;
CREATE POLICY reward_points_owner_profiles_select
ON public.profiles
FOR SELECT
TO reward_points_owner
USING (true);

DROP POLICY IF EXISTS reward_points_owner_ad_settings_select ON public.ad_settings;
CREATE POLICY reward_points_owner_ad_settings_select
ON public.ad_settings
FOR SELECT
TO reward_points_owner
USING (true);

NOTIFY pgrst, 'reload schema';

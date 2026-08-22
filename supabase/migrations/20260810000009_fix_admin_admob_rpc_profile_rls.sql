-- =============================================================================
-- FINAL SQL EDITOR FIX: make the admin profile check independent from profiles RLS.
-- Run this whole file once in Supabase SQL Editor.
-- =============================================================================

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
  p_admin_reporting_enabled boolean DEFAULT false,
  p_admob_app_id_android text DEFAULT NULL,
  p_admob_app_id_ios text DEFAULT NULL,
  p_admob_rewarded_unit_id_android text DEFAULT NULL,
  p_admob_rewarded_unit_id_ios text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  -- PostgREST puts the verified JWT claims into transaction-local settings.
  -- Reading the signed subject here avoids any dependency on the auth schema from the
  -- constrained reward_points_owner execution context.
  v_admin uuid := COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
    NULLIF(current_setting('request.jwt.claim.sub', true), '')
  )::uuid;
  v_old jsonb;
  v_new jsonb;
  v_app_android text := NULLIF(btrim(p_admob_app_id_android), '');
  v_app_ios text := NULLIF(btrim(p_admob_app_id_ios), '');
  v_unit_android text := NULLIF(btrim(p_admob_rewarded_unit_id_android), '');
  v_unit_ios text := NULLIF(btrim(p_admob_rewarded_unit_id_ios), '');
BEGIN
  IF v_admin IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = v_admin
      AND (p.role::text = 'admin' OR COALESCE(p.is_admin, false))
  ) THEN
    RAISE EXCEPTION 'ADMIN_REQUIRED' USING ERRCODE = '42501';
  END IF;

  IF p_reward_min_points IS NULL OR p_reward_max_points IS NULL
     OR p_max_daily_reward_points IS NULL OR p_points_per_try IS NULL
     OR p_test_mode IS NULL OR p_reward_feature_mode IS NULL
     OR p_earn_enabled IS NULL OR p_ssv_enabled IS NULL
     OR p_spend_enabled IS NULL OR p_eligible_products_enabled IS NULL
     OR p_reason IS NULL OR p_max_views_per_day IS NULL
     OR p_max_views_per_hour IS NULL OR p_cooldown_seconds IS NULL
     OR p_admin_reporting_enabled IS NULL
     OR p_reward_min_points <= 0
     OR p_reward_max_points <> p_reward_min_points
     OR p_max_daily_reward_points < 0
     OR p_points_per_try <= 0
     OR p_points_per_try % 100 <> 0
     OR p_max_views_per_day < 1
     OR p_max_views_per_hour < 1
     OR p_cooldown_seconds < 0
     OR p_reward_feature_mode NOT IN ('disabled', 'observe', 'cohort', 'enabled')
     OR length(btrim(p_reason)) NOT BETWEEN 8 AND 1000 THEN
    RAISE EXCEPTION 'INVALID_REWARD_CONFIG' USING ERRCODE = '22023';
  END IF;

  IF (v_app_android IS NOT NULL
      AND v_app_android !~ '^ca-app-pub-[0-9]{16}~[0-9]{10}$')
     OR (v_app_ios IS NOT NULL
      AND v_app_ios !~ '^ca-app-pub-[0-9]{16}~[0-9]{10}$')
     OR (v_unit_android IS NOT NULL
      AND v_unit_android !~ '^ca-app-pub-[0-9]{16}/[0-9]{10}$')
     OR (v_unit_ios IS NOT NULL
      AND v_unit_ios !~ '^ca-app-pub-[0-9]{16}/[0-9]{10}$') THEN
    RAISE EXCEPTION 'INVALID_ADMOB_IDENTIFIER' USING ERRCODE = '22023';
  END IF;

  IF p_test_mode AND p_earn_enabled THEN
    RAISE EXCEPTION 'TEST_MODE_CANNOT_EARN' USING ERRCODE = '22023';
  END IF;

  IF NOT p_test_mode
     AND p_reward_feature_mode = 'enabled'
     AND (v_unit_android IS NULL OR v_unit_ios IS NULL) THEN
    RAISE EXCEPTION 'PRODUCTION_AD_UNITS_REQUIRED' USING ERRCODE = '22023';
  END IF;

  IF p_earn_enabled
     AND (NOT p_ssv_enabled OR p_reward_feature_mode <> 'enabled') THEN
    RAISE EXCEPTION 'SSV_REQUIRED_FOR_EARN' USING ERRCODE = '22023';
  END IF;

  SELECT to_jsonb(s)
  INTO v_old
  FROM public.ad_settings AS s
  WHERE s.id = 1
  FOR UPDATE;

  IF v_old IS NULL THEN
    RAISE EXCEPTION 'REWARD_CONFIG_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.ad_settings AS s
  SET reward_min_points = p_reward_min_points,
      reward_max_points = p_reward_max_points,
      max_daily_reward_points = p_max_daily_reward_points,
      points_per_try = p_points_per_try,
      test_mode = p_test_mode,
      admob_app_id_android = v_app_android,
      admob_app_id_ios = v_app_ios,
      admob_rewarded_unit_id_android = v_unit_android,
      admob_rewarded_unit_id_ios = v_unit_ios,
      reward_feature_mode = p_reward_feature_mode,
      reward_points_earn_enabled = p_earn_enabled,
      reward_points_ssv_enabled = p_ssv_enabled,
      reward_points_spend_enabled = p_spend_enabled,
      reward_points_eligible_products_enabled = p_eligible_products_enabled,
      reward_points_admin_reporting_enabled = p_admin_reporting_enabled,
      max_views_per_day = p_max_views_per_day,
      max_views_per_hour = p_max_views_per_hour,
      cooldown_seconds = p_cooldown_seconds,
      reward_policy_version = s.reward_policy_version + 1,
      legacy_ad_tl_grant_disabled = true,
      is_enabled = false,
      updated_at = clock_timestamp()
  WHERE s.id = 1
  RETURNING to_jsonb(s) INTO v_new;

  INSERT INTO public.reward_points_config_audit(
    admin_user_id,
    old_config,
    new_config,
    reason
  ) VALUES (
    v_admin,
    v_old,
    v_new,
    btrim(p_reason)
  );

  RETURN v_new;
END;
$$;

ALTER FUNCTION public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean,
  boolean, boolean, text, integer, integer, integer, boolean,
  text, text, text, text
) OWNER TO reward_points_owner;

REVOKE ALL ON FUNCTION public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean,
  boolean, boolean, text, integer, integer, integer, boolean,
  text, text, text, text
) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean,
  boolean, boolean, text, integer, integer, integer, boolean,
  text, text, text, text
) TO authenticated;

GRANT SELECT ON public.profiles TO reward_points_owner;
GRANT SELECT, UPDATE ON public.ad_settings TO reward_points_owner;
GRANT INSERT ON public.reward_points_config_audit TO reward_points_owner;

-- profiles has RLS and an earlier privacy hardening migration deliberately
-- removed this constrained-owner policy. Without it, SECURITY DEFINER runs as
-- reward_points_owner but sees zero profile rows and raises ADMIN_REQUIRED even
-- for a real admin. This role is NOLOGIN and receives only SELECT, so the policy
-- does not expose profiles through PostgREST.
DROP POLICY IF EXISTS reward_points_owner_profiles_select ON public.profiles;
CREATE POLICY reward_points_owner_profiles_select
ON public.profiles
FOR SELECT
TO reward_points_owner
USING (true);

NOTIFY pgrst, 'reload schema';


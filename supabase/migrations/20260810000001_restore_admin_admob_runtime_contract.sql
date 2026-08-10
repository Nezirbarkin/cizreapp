-- =============================================================================
-- Restore the canonical admin-managed AdMob runtime contract.
--
-- 20260804000002_fill_app_contract_gaps.sql replayed an older reward-points
-- contract after 20260801000002_admin_admob_runtime_settings.sql. That replay
-- left obsolete RPC overloads in the catalog and removed rewarded unit IDs from
-- reward_points_public_config. Mobile clients consequently failed closed before
-- loading a production rewarded ad. This migration makes the final catalog
-- state deterministic regardless of that historical replay.
-- =============================================================================

GRANT USAGE, CREATE ON SCHEMA public TO reward_points_owner;

-- Remove every historical overload. Keeping both the 15- and 19-argument forms
-- makes PostgREST schema discovery ambiguous and permits old clients to mutate
-- only part of the current configuration contract.
DROP FUNCTION IF EXISTS public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean, boolean, boolean, text
) CASCADE;
DROP FUNCTION IF EXISTS public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean, boolean, boolean, text,
  integer, integer, integer, boolean
) CASCADE;
DROP FUNCTION IF EXISTS public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean, boolean, boolean, text,
  integer, integer, integer, boolean, text, text, text, text
) CASCADE;

CREATE FUNCTION public.admin_update_reward_points_config(
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
  v_admin uuid := auth.uid();
  v_old jsonb;
  v_new jsonb;
  v_app_android text := NULLIF(btrim(p_admob_app_id_android), '');
  v_app_ios text := NULLIF(btrim(p_admob_app_id_ios), '');
  v_unit_android text := NULLIF(btrim(p_admob_rewarded_unit_id_android), '');
  v_unit_ios text := NULLIF(btrim(p_admob_rewarded_unit_id_ios), '');
BEGIN
  IF v_admin IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles AS p WHERE p.id = v_admin AND p.role = 'admin'
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
     OR p_reward_min_points <= 0 OR p_reward_max_points <> p_reward_min_points
     OR p_max_daily_reward_points < 0 OR p_points_per_try <= 0
     OR p_points_per_try % 100 <> 0
     OR p_max_views_per_day < 1 OR p_max_views_per_hour < 1
     OR p_cooldown_seconds < 0
     OR p_reward_feature_mode NOT IN ('disabled', 'observe', 'cohort', 'enabled')
     OR length(btrim(p_reason)) NOT BETWEEN 8 AND 1000 THEN
    RAISE EXCEPTION 'INVALID_REWARD_CONFIG' USING ERRCODE = '22023';
  END IF;

  IF (v_app_android IS NOT NULL AND v_app_android !~ '^ca-app-pub-[0-9]{16}~[0-9]{10}$')
     OR (v_app_ios IS NOT NULL AND v_app_ios !~ '^ca-app-pub-[0-9]{16}~[0-9]{10}$')
     OR (v_unit_android IS NOT NULL AND v_unit_android !~ '^ca-app-pub-[0-9]{16}/[0-9]{10}$')
     OR (v_unit_ios IS NOT NULL AND v_unit_ios !~ '^ca-app-pub-[0-9]{16}/[0-9]{10}$') THEN
    RAISE EXCEPTION 'INVALID_ADMOB_IDENTIFIER' USING ERRCODE = '22023';
  END IF;
  IF p_test_mode AND p_earn_enabled THEN
    RAISE EXCEPTION 'TEST_MODE_CANNOT_EARN' USING ERRCODE = '22023';
  END IF;
  IF NOT p_test_mode AND p_reward_feature_mode = 'enabled'
     AND (v_unit_android IS NULL OR v_unit_ios IS NULL) THEN
    RAISE EXCEPTION 'PRODUCTION_AD_UNITS_REQUIRED' USING ERRCODE = '22023';
  END IF;
  IF p_earn_enabled AND (NOT p_ssv_enabled OR p_reward_feature_mode <> 'enabled') THEN
    RAISE EXCEPTION 'SSV_REQUIRED_FOR_EARN' USING ERRCODE = '22023';
  END IF;

  SELECT to_jsonb(s) INTO v_old
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
    admin_user_id, old_config, new_config, reason
  ) VALUES (
    v_admin, v_old, v_new, btrim(p_reason)
  );

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean, boolean, boolean, text,
  integer, integer, integer, boolean, text, text, text, text
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean, boolean, boolean, text,
  integer, integer, integer, boolean, text, text, text, text
) TO authenticated;
ALTER FUNCTION public.admin_update_reward_points_config(
  integer, integer, bigint, integer, boolean, text, boolean, boolean, boolean, boolean, text,
  integer, integer, integer, boolean, text, text, text, text
) OWNER TO reward_points_owner;

-- Rewarded unit IDs are placement identifiers consumed by authenticated mobile
-- clients, not credentials. Native App IDs and all SSV secrets remain excluded.
CREATE OR REPLACE VIEW public.reward_points_public_config
WITH (security_invoker = true) AS
SELECT id, test_mode, reward_min_points, reward_max_points,
  max_daily_reward_points, points_per_try, reward_policy_version,
  reward_feature_mode, reward_points_schema_ready, reward_points_earn_enabled,
  reward_points_ssv_required, reward_points_ssv_enabled,
  reward_points_spend_enabled, reward_points_eligible_products_enabled,
  reward_points_admin_reporting_enabled, legacy_ad_tl_grant_disabled,
  max_views_per_day, max_views_per_hour, cooldown_seconds,
  admob_rewarded_unit_id_android, admob_rewarded_unit_id_ios
FROM public.ad_settings
WHERE id = 1;

REVOKE ALL ON public.reward_points_public_config FROM PUBLIC, anon;
GRANT SELECT ON public.reward_points_public_config TO authenticated;

REVOKE ALL ON public.ad_settings FROM anon, authenticated;
GRANT SELECT (
  id, test_mode, reward_min_points, reward_max_points,
  max_daily_reward_points, points_per_try, reward_policy_version,
  reward_feature_mode, reward_points_schema_ready, reward_points_earn_enabled,
  reward_points_ssv_required, reward_points_ssv_enabled,
  reward_points_spend_enabled, reward_points_eligible_products_enabled,
  reward_points_admin_reporting_enabled, legacy_ad_tl_grant_disabled,
  max_views_per_day, max_views_per_hour, cooldown_seconds,
  admob_rewarded_unit_id_android, admob_rewarded_unit_id_ios
) ON public.ad_settings TO authenticated;

REVOKE CREATE ON SCHEMA public FROM reward_points_owner;

NOTIFY pgrst, 'reload schema';


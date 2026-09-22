-- =============================================================================
-- DÜZELTME: Google SSV callback'inin sayısal `ad_unit` değeri DB'de reddediliyordu
-- =============================================================================
-- BULGU (2026-09-21, canlı DB'de kendini geri alan simülasyonla doğrulandı):
--   Google'ın SSV callback'i `ad_unit` parametresinde yalnız SAYISAL kimliği
--   yollar (belge örneği: ad_unit=2747237135). admob-ssv-callback Edge
--   Function'ı bu değeri olduğu gibi grant_verified_ad_points'e geçiriyor ve
--   fonksiyon onu ad_settings'teki TAM kimlikle
--   (ca-app-pub-3604161523594294/3456629893) karşılaştırıyordu. Sayısal değer
--   hiçbir zaman tam kimliğe eşit olmadığından, AdMob hesabı onaylanıp reklam
--   yayınlanmaya başladığında bile HER gerçek ödül
--   status='rejected' / verification_error_code='AD_UNIT_NOT_ALLOWED' ile
--   düşecekti: kullanıcı reklamı izler, puan yazılmazdı.
--   (Bugüne dek ad_reward_ssv_events tablosu boş olduğundan hata hiç görülmedi.)
--
-- DÜZELTME: hem tam kimlik hem de onun sayısal son eki kabul edilir. Başka her
--   değer (yanlış birim, başka yayıncının kimliği, boş) eskisi gibi reddedilir.
--   Fonksiyonun geri kalanı, sahibi (reward_points_owner) ve yetkileri
--   (yalnız service_role EXECUTE) DEĞİŞMEZ; CREATE OR REPLACE bunları korur.
--
-- Doğrulama betiği: supabase/tests/manual/admob_ssv_ad_unit_numeric_test.sql
-- =============================================================================

begin;

CREATE OR REPLACE FUNCTION public.grant_verified_ad_points(p_reward_session_id uuid, p_provider_transaction_id text, p_provider_transaction_hash text, p_ad_unit_id text, p_signature_key_id text, p_callback_timestamp timestamp with time zone, p_custom_data_nonce_hash text, p_provider_user_id_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_session public.ad_reward_sessions%ROWTYPE;
  v_settings public.ad_settings%ROWTYPE;
  v_budget public.ad_reward_daily_budgets%ROWTYPE;
  v_entry public.point_ledger_entries%ROWTYPE;
  v_points integer;
  v_today_count integer;
  v_hour_count integer;
  v_last_credit timestamptz;
  v_event_id uuid;
  v_existing_event public.ad_reward_ssv_events%ROWTYPE;
BEGIN
  IF COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    ''
  ) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF p_custom_data_nonce_hash IS NULL
     OR p_custom_data_nonce_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'INVALID_CUSTOM_DATA_NONCE_HASH' USING ERRCODE = '22023';
  END IF;
  IF p_provider_transaction_id IS NULL
     OR p_provider_transaction_id !~ '^[0-9a-f]{64}$'
     OR p_provider_transaction_hash IS NULL
     OR p_provider_transaction_hash !~ '^[0-9a-f]{64}$'
     OR lower(p_provider_transaction_id) IS DISTINCT FROM lower(p_provider_transaction_hash) THEN
    RAISE EXCEPTION 'INVALID_PROVIDER_TRANSACTION' USING ERRCODE = '22023';
  END IF;

  -- Provider transaction replay checks must serialize globally, not only per user.
  PERFORM pg_advisory_xact_lock(hashtextextended(lower(p_provider_transaction_id), 71000));
  SELECT se.* INTO v_existing_event
  FROM public.ad_reward_ssv_events AS se
  WHERE se.ad_network = 'admob'
    AND se.provider_transaction_id = lower(p_provider_transaction_id);
  IF FOUND THEN
    SELECT rs.* INTO STRICT v_session
    FROM public.ad_reward_sessions AS rs
    WHERE rs.id = v_existing_event.session_id;
    IF p_reward_session_id IS DISTINCT FROM v_session.id
       OR p_custom_data_nonce_hash IS DISTINCT FROM v_session.custom_data_nonce_hash
       OR lower(p_provider_transaction_hash) IS DISTINCT FROM v_existing_event.provider_transaction_hash THEN
      RETURN jsonb_build_object('reward_session_id', p_reward_session_id, 'status', 'rejected',
        'reward_points', NULL, 'new_point_balance', NULL, 'duplicate', true);
    END IF;
    RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', v_session.status,
      'reward_points', v_session.credited_points,
      'new_point_balance', (SELECT a.balance_points FROM public.user_point_accounts AS a WHERE a.user_id = v_session.user_id),
      'duplicate', true);
  END IF;
  IF p_callback_timestamp < clock_timestamp() - interval '1 day'
     OR p_callback_timestamp > clock_timestamp() + interval '5 minutes' THEN
    RAISE EXCEPTION 'SSV_TIMESTAMP_REJECTED' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_session
  FROM public.ad_reward_sessions AS rs
  WHERE rs.id = p_reward_session_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REWARD_SESSION_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF p_custom_data_nonce_hash IS DISTINCT FROM v_session.custom_data_nonce_hash THEN
    RAISE EXCEPTION 'SSV_CUSTOM_DATA_MISMATCH' USING ERRCODE = '22023';
  END IF;
  IF v_session.status = 'credited' THEN
    RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', 'credited',
      'reward_points', v_session.credited_points,
      'new_point_balance', (SELECT a.balance_points FROM public.user_point_accounts AS a WHERE a.user_id = v_session.user_id),
      'duplicate', true);
  END IF;
  IF v_session.status <> 'pending_ssv' THEN
    RETURN jsonb_build_object('reward_session_id', v_session.id,
      'status', CASE WHEN v_session.status IN ('blocked', 'rejected', 'expired')
        THEN v_session.status ELSE 'rejected' END,
      'reward_points', NULL,
      'new_point_balance', (SELECT a.balance_points FROM public.user_point_accounts AS a WHERE a.user_id = v_session.user_id),
      'duplicate', false);
  END IF;

  SELECT * INTO v_settings FROM public.ad_settings AS s WHERE s.id = 1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'REWARD_SETTINGS_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

  -- Persist every cryptographically verified provider event before applying
  -- product limits. Permanent business rejections then return 2xx to Google and
  -- can never become an economic credit after a later retry.
  INSERT INTO public.ad_reward_ssv_events (
    session_id, provider_transaction_id, provider_transaction_hash,
    provider_user_id_hash, ad_unit_id, signature_key_id, callback_timestamp,
    signature_verified, retention_expires_at
  ) VALUES (
    v_session.id, lower(p_provider_transaction_id), lower(p_provider_transaction_hash),
    lower(p_provider_user_id_hash), p_ad_unit_id, p_signature_key_id, p_callback_timestamp,
    true, clock_timestamp() + make_interval(days => v_settings.fraud_hash_retention_days)
  ) RETURNING id INTO v_event_id;

  IF v_session.expires_at < clock_timestamp() THEN
    UPDATE public.ad_reward_sessions SET status = 'expired', updated_at = clock_timestamp() WHERE id = v_session.id;
    UPDATE public.ad_reward_ssv_events SET verification_error_code = 'SESSION_EXPIRED' WHERE id = v_event_id;
    -- Returning instead of raising is intentional: an exception would roll
    -- the status update back and leave the session pending forever.
    RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', 'expired',
      'reward_points', NULL,
      'new_point_balance', (SELECT a.balance_points FROM public.user_point_accounts AS a WHERE a.user_id = v_session.user_id),
      'duplicate', false);
  END IF;

  IF v_settings.test_mode
     OR NOT v_settings.reward_points_schema_ready
     OR NOT v_settings.reward_points_earn_enabled
     OR NOT v_settings.reward_points_ssv_required
     OR NOT v_settings.reward_points_ssv_enabled
     OR NOT v_settings.legacy_ad_tl_grant_disabled
     OR v_settings.reward_feature_mode <> 'enabled' THEN
    UPDATE public.ad_reward_sessions SET status = 'blocked', updated_at = clock_timestamp() WHERE id = v_session.id;
    UPDATE public.ad_reward_ssv_events SET verification_error_code = 'REWARD_EARN_NOT_READY' WHERE id = v_event_id;
    RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', 'blocked',
      'reward_points', NULL, 'new_point_balance', NULL, 'duplicate', false);
  END IF;
  -- Google SSV callback'i `ad_unit` alanında YALNIZ sayısal kısmı yollar
  -- (ör. 3456629893). ad_settings ise SDK'nın istediği TAM kimliği saklar
  -- (ca-app-pub-XXXXXXXXXXXXXXXX/3456629893). Eskiden yalnız tam kimlik
  -- kabul edildiği için gerçek her callback AD_UNIT_NOT_ALLOWED ile
  -- reddediliyordu. Şimdi ikisi de kabul edilir; başka her değer reddedilir.
  IF p_ad_unit_id IS DISTINCT FROM v_settings.admob_rewarded_unit_id_android
     AND p_ad_unit_id IS DISTINCT FROM v_settings.admob_rewarded_unit_id_ios
     AND p_ad_unit_id IS DISTINCT FROM NULLIF(split_part(v_settings.admob_rewarded_unit_id_android, '/', 2), '')
     AND p_ad_unit_id IS DISTINCT FROM NULLIF(split_part(v_settings.admob_rewarded_unit_id_ios, '/', 2), '') THEN
    UPDATE public.ad_reward_sessions SET status = 'rejected', updated_at = clock_timestamp() WHERE id = v_session.id;
    UPDATE public.ad_reward_ssv_events SET verification_error_code = 'AD_UNIT_NOT_ALLOWED' WHERE id = v_event_id;
    RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', 'rejected',
      'reward_points', NULL, 'new_point_balance', NULL, 'duplicate', false);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_session.user_id::text, 71001));
  SELECT count(*) FILTER (WHERE rs.credited_at >= date_trunc('day', clock_timestamp())),
         count(*) FILTER (WHERE rs.credited_at >= clock_timestamp() - interval '1 hour'),
         max(rs.credited_at)
    INTO v_today_count, v_hour_count, v_last_credit
  FROM public.ad_reward_sessions AS rs
  WHERE rs.user_id = v_session.user_id AND rs.status = 'credited';
  IF v_today_count >= v_settings.max_views_per_day OR v_hour_count >= v_settings.max_views_per_hour THEN
    UPDATE public.ad_reward_sessions SET status = 'blocked', updated_at = clock_timestamp() WHERE id = v_session.id;
    UPDATE public.ad_reward_ssv_events SET verification_error_code = 'REWARD_USER_LIMIT' WHERE id = v_event_id;
    RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', 'blocked',
      'reward_points', NULL, 'new_point_balance', NULL, 'duplicate', false);
  END IF;
  IF v_last_credit IS NOT NULL
     AND v_last_credit > clock_timestamp() - make_interval(secs => v_settings.cooldown_seconds) THEN
    UPDATE public.ad_reward_sessions SET status = 'blocked', updated_at = clock_timestamp() WHERE id = v_session.id;
    UPDATE public.ad_reward_ssv_events SET verification_error_code = 'REWARD_COOLDOWN' WHERE id = v_event_id;
    RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', 'blocked',
      'reward_points', NULL, 'new_point_balance', NULL, 'duplicate', false);
  END IF;

  v_points := v_session.reward_points_snapshot;
  INSERT INTO public.ad_reward_daily_budgets(budget_date)
  VALUES ((clock_timestamp() AT TIME ZONE 'UTC')::date)
  ON CONFLICT (budget_date) DO NOTHING;
  SELECT * INTO v_budget FROM public.ad_reward_daily_budgets AS b
  WHERE b.budget_date = (clock_timestamp() AT TIME ZONE 'UTC')::date FOR UPDATE;
  IF v_budget.granted_points + v_points > v_settings.max_daily_reward_points THEN
    UPDATE public.ad_reward_sessions SET status = 'blocked', updated_at = clock_timestamp() WHERE id = v_session.id;
    UPDATE public.ad_reward_ssv_events SET verification_error_code = 'REWARD_DAILY_BUDGET_EXHAUSTED' WHERE id = v_event_id;
    RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', 'blocked',
      'reward_points', NULL, 'new_point_balance', NULL, 'duplicate', false);
  END IF;

  v_entry := public.reward_points_apply_entry(
    v_session.user_id, 'ad_reward_credit', 'credit', v_points,
    'ad_reward_session', v_session.id, 'admob:' || p_provider_transaction_hash,
    jsonb_build_object('ssv_event_id', v_event_id, 'policy_version', v_session.policy_version)
  );
  UPDATE public.ad_reward_daily_budgets
  SET granted_points = granted_points + v_points, grant_count = grant_count + 1,
      updated_at = clock_timestamp()
  WHERE budget_date = v_budget.budget_date;
  UPDATE public.ad_reward_sessions
  SET status = 'credited', credited_points = v_points, point_ledger_entry_id = v_entry.id,
      credited_at = clock_timestamp(), updated_at = clock_timestamp()
  WHERE id = v_session.id;

  RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', 'credited',
    'reward_points', v_points, 'new_point_balance', v_entry.balance_after_points, 'duplicate', false);
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO v_session FROM public.ad_reward_sessions AS rs WHERE rs.id = p_reward_session_id;
  IF v_session.status = 'credited' THEN
    RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', 'credited',
      'reward_points', v_session.credited_points,
      'new_point_balance', (SELECT a.balance_points FROM public.user_point_accounts AS a WHERE a.user_id = v_session.user_id),
      'duplicate', true);
  END IF;
  RAISE;
END;
$function$;

commit;

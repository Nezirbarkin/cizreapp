-- =============================================================================
-- AdMob SSV reward points, mixed digital checkout and source-preserving refunds
-- Additive migration. Historical TL ad rewards are audit-only and are NOT copied.
-- =============================================================================

DO $migration$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'reward_points_owner') THEN
    -- Supabase migration'ları çoğunlukla postgres olarak çalışır. PostgreSQL 16+
    -- non-superuser CREATEROLE sahibine yeni rol üzerinde ADMIN verir ancak SET
    -- yetkisi vermez. CREATE ROLE ... ADMIN postgres ise ADMIN'i kendi grantor'ına
    -- geri vermeye çalıştığı için 0LP01 üretir; rolü önce yalın olarak oluştur.
    CREATE ROLE reward_points_owner NOLOGIN NOINHERIT;
  END IF;
  -- ALTER ... OWNER TO, hedef role SET ROLE yapabilmeyi zorunlu tutar. MEMBER
  -- kontrolü burada yeterli değildir: otomatik ADMIN üyeliği SET FALSE olabilir.
  IF NOT pg_has_role(current_user, 'reward_points_owner', 'SET') THEN
    EXECUTE format(
      'GRANT reward_points_owner TO %I WITH SET TRUE',
      current_user
    );
  END IF;
END
$migration$;

-- PostgreSQL requires a prospective object owner to have CREATE on the
-- containing schema. This is temporary and revoked after ownership transfer.
GRANT USAGE, CREATE ON SCHEMA public TO reward_points_owner;
GRANT USAGE ON SCHEMA auth TO reward_points_owner;

-- -----------------------------------------------------------------------------
-- Configuration and cutover. Legacy monetary columns remain audit-only.
-- -----------------------------------------------------------------------------
ALTER TABLE public.ad_settings
  ADD COLUMN IF NOT EXISTS reward_min_points integer NOT NULL DEFAULT 10 CHECK (reward_min_points > 0),
  ADD COLUMN IF NOT EXISTS reward_max_points integer NOT NULL DEFAULT 10 CHECK (reward_max_points > 0),
  ADD COLUMN IF NOT EXISTS max_daily_reward_points bigint NOT NULL DEFAULT 500000 CHECK (max_daily_reward_points >= 0),
  ADD COLUMN IF NOT EXISTS points_per_try integer NOT NULL DEFAULT 100 CHECK (points_per_try > 0),
  ADD COLUMN IF NOT EXISTS reward_policy_version integer NOT NULL DEFAULT 1 CHECK (reward_policy_version > 0),
  ADD COLUMN IF NOT EXISTS reward_feature_mode text NOT NULL DEFAULT 'disabled'
    CHECK (reward_feature_mode IN ('disabled', 'observe', 'cohort', 'enabled')),
  ADD COLUMN IF NOT EXISTS reward_points_schema_ready boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS reward_points_earn_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reward_points_ssv_required boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS reward_points_ssv_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reward_points_spend_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reward_points_eligible_products_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reward_points_admin_reporting_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS legacy_ad_tl_grant_disabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS migration_cutover_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ADD COLUMN IF NOT EXISTS fraud_hash_retention_days integer NOT NULL DEFAULT 30
    CHECK (fraud_hash_retention_days BETWEEN 1 AND 365);

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conname = 'ad_settings_reward_points_range_check'
      AND conrelid = 'public.ad_settings'::regclass
  ) THEN
    ALTER TABLE public.ad_settings
      ADD CONSTRAINT ad_settings_reward_points_range_check
      CHECK (reward_max_points = reward_min_points);
  END IF;
END
$migration$;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conname = 'ad_settings_points_per_try_cents_check'
      AND conrelid = 'public.ad_settings'::regclass
  ) THEN
    ALTER TABLE public.ad_settings
      ADD CONSTRAINT ad_settings_points_per_try_cents_check
      CHECK (points_per_try % 100 = 0);
  END IF;
END
$migration$;

UPDATE public.ad_settings
SET is_enabled = false,
    legacy_ad_tl_grant_disabled = true,
    reward_points_earn_enabled = false,
    reward_points_spend_enabled = false,
    reward_feature_mode = 'disabled',
    migration_cutover_at = COALESCE(migration_cutover_at, clock_timestamp()),
    updated_at = clock_timestamp()
WHERE id = 1;

CREATE TABLE public.reward_points_config_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id uuid NOT NULL REFERENCES public.profiles(id),
  old_config jsonb NOT NULL,
  new_config jsonb NOT NULL,
  reason text NOT NULL CHECK (length(reason) BETWEEN 8 AND 1000),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- -----------------------------------------------------------------------------
-- Integer account projection and immutable append-only ledger.
-- -----------------------------------------------------------------------------
CREATE TABLE public.user_point_accounts (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  balance_points bigint NOT NULL DEFAULT 0 CHECK (balance_points >= 0),
  lifetime_earned_points bigint NOT NULL DEFAULT 0 CHECK (lifetime_earned_points >= 0),
  lifetime_spent_points bigint NOT NULL DEFAULT 0 CHECK (lifetime_spent_points >= 0),
  lifetime_refunded_points bigint NOT NULL DEFAULT 0 CHECK (lifetime_refunded_points >= 0),
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.point_ledger_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  entry_type text NOT NULL CHECK (entry_type IN (
    'ad_reward_credit', 'digital_order_debit', 'digital_order_refund',
    'admin_correction_credit', 'admin_correction_debit', 'expiry_debit'
  )),
  direction text NOT NULL CHECK (direction IN ('credit', 'debit')),
  points bigint NOT NULL CHECK (points > 0),
  balance_before_points bigint NOT NULL CHECK (balance_before_points >= 0),
  balance_after_points bigint NOT NULL CHECK (balance_after_points >= 0),
  reference_type text NOT NULL CHECK (reference_type IN ('ad_reward_session', 'digital_order', 'admin_case')),
  reference_id uuid NOT NULL,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 200),
  reversal_of_entry_id uuid UNIQUE REFERENCES public.point_ledger_entries(id) ON DELETE RESTRICT,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(metadata::text) <= 8192),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT point_ledger_balance_math CHECK (
    (direction = 'credit' AND balance_after_points = balance_before_points + points)
    OR (direction = 'debit' AND balance_after_points = balance_before_points - points)
  ),
  CONSTRAINT point_ledger_type_direction CHECK (
    (entry_type IN ('ad_reward_credit', 'digital_order_refund', 'admin_correction_credit') AND direction = 'credit')
    OR (entry_type IN ('digital_order_debit', 'admin_correction_debit', 'expiry_debit') AND direction = 'debit')
  ),
  CONSTRAINT point_ledger_no_sensitive_metadata CHECK (
    NOT (metadata ?| ARRAY['ip', 'ip_address', 'device_id', 'signature', 'raw_query', 'provider_user_id'])
  ),
  UNIQUE (idempotency_key)
);

CREATE INDEX point_ledger_entries_user_created_idx
  ON public.point_ledger_entries(user_id, created_at DESC);
CREATE UNIQUE INDEX point_ledger_one_ad_credit_idx
  ON public.point_ledger_entries(reference_id)
  WHERE entry_type = 'ad_reward_credit';
CREATE UNIQUE INDEX point_ledger_one_order_debit_idx
  ON public.point_ledger_entries(reference_id)
  WHERE entry_type = 'digital_order_debit';

CREATE OR REPLACE FUNCTION public.reject_point_ledger_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'POINT_LEDGER_IMMUTABLE' USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER point_ledger_reject_update_delete
BEFORE UPDATE OR DELETE ON public.point_ledger_entries
FOR EACH ROW EXECUTE FUNCTION public.reject_point_ledger_mutation();

CREATE TRIGGER point_ledger_reject_truncate
BEFORE TRUNCATE ON public.point_ledger_entries
FOR EACH STATEMENT EXECUTE FUNCTION public.reject_point_ledger_mutation();

-- -----------------------------------------------------------------------------
-- Reward sessions, verified provider events, atomic daily budget and retention.
-- Only HMAC/hash pseudonyms are accepted; raw IP/device/provider user identifiers
-- have no columns in these tables.
-- -----------------------------------------------------------------------------
CREATE TABLE public.ad_reward_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  custom_data_nonce_hash text NOT NULL CHECK (custom_data_nonce_hash ~ '^[0-9a-f]{64}$'),
  client_idempotency_key text NOT NULL CHECK (length(client_idempotency_key) BETWEEN 8 AND 200),
  device_pseudonym_hash text CHECK (device_pseudonym_hash IS NULL OR device_pseudonym_hash ~ '^[0-9a-f]{64}$'),
  network_pseudonym_hash text CHECK (network_pseudonym_hash IS NULL OR network_pseudonym_hash ~ '^[0-9a-f]{64}$'),
  status text NOT NULL DEFAULT 'initiated' CHECK (status IN (
    'initiated', 'pending_ssv', 'verified', 'credited', 'blocked', 'rejected', 'duplicate', 'expired'
  )),
  expires_at timestamptz NOT NULL,
  reward_points_snapshot integer NOT NULL CHECK (reward_points_snapshot > 0),
  credited_points integer CHECK (credited_points IS NULL OR credited_points > 0),
  point_ledger_entry_id uuid UNIQUE REFERENCES public.point_ledger_entries(id) ON DELETE RESTRICT,
  policy_version integer NOT NULL CHECK (policy_version > 0),
  credited_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (user_id, client_idempotency_key),
  UNIQUE (custom_data_nonce_hash)
);

CREATE INDEX ad_reward_sessions_user_created_idx
  ON public.ad_reward_sessions(user_id, created_at DESC);
CREATE INDEX ad_reward_sessions_user_credited_idx
  ON public.ad_reward_sessions(user_id, credited_at DESC)
  WHERE status = 'credited';
CREATE INDEX ad_reward_sessions_expiry_idx
  ON public.ad_reward_sessions(expires_at) WHERE status IN ('initiated', 'pending_ssv');

CREATE TABLE public.ad_reward_ssv_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.ad_reward_sessions(id) ON DELETE RESTRICT,
  ad_network text NOT NULL DEFAULT 'admob' CHECK (ad_network = 'admob'),
  provider_transaction_id text NOT NULL CHECK (provider_transaction_id ~ '^[0-9a-f]{64}$'),
  provider_transaction_hash text NOT NULL CHECK (provider_transaction_hash ~ '^[0-9a-f]{64}$'),
  provider_user_id_hash text CHECK (provider_user_id_hash IS NULL OR provider_user_id_hash ~ '^[0-9a-f]{64}$'),
  ad_unit_id text NOT NULL CHECK (length(ad_unit_id) BETWEEN 1 AND 255),
  signature_key_id text NOT NULL CHECK (length(signature_key_id) BETWEEN 1 AND 100),
  callback_timestamp timestamptz NOT NULL,
  signature_verified boolean NOT NULL CHECK (signature_verified),
  verification_error_code text,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  verified_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  retention_expires_at timestamptz NOT NULL,
  UNIQUE (ad_network, provider_transaction_id),
  UNIQUE (session_id)
);

CREATE INDEX ad_reward_ssv_events_retention_idx
  ON public.ad_reward_ssv_events(retention_expires_at);

CREATE TABLE public.ad_reward_daily_budgets (
  budget_date date PRIMARY KEY,
  granted_points bigint NOT NULL DEFAULT 0 CHECK (granted_points >= 0),
  grant_count bigint NOT NULL DEFAULT 0 CHECK (grant_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.reward_points_migration_audits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cutover_at timestamptz NOT NULL,
  historical_success_count bigint NOT NULL,
  historical_reward_amount_try numeric(18,2) NOT NULL,
  linked_balance_transaction_count bigint NOT NULL,
  orphan_balance_transaction_count bigint NOT NULL,
  notes text NOT NULL DEFAULT 'Grandfathered TL retained; no point backfill performed.',
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (cutover_at)
);

INSERT INTO public.reward_points_migration_audits (
  cutover_at, historical_success_count, historical_reward_amount_try,
  linked_balance_transaction_count, orphan_balance_transaction_count
)
SELECT s.migration_cutover_at,
       count(v.id),
       COALESCE(sum(v.reward_amount), 0),
       count(v.balance_transaction_id),
       count(v.id) FILTER (WHERE v.balance_transaction_id IS NULL)
FROM public.ad_settings AS s
LEFT JOIN public.ad_reward_views AS v
  ON v.created_at < s.migration_cutover_at AND v.status = 'success'
WHERE s.id = 1
GROUP BY s.migration_cutover_at
ON CONFLICT (cutover_at) DO NOTHING;

-- Existing view table is retained for grandfather audit, with point linkage only.
ALTER TABLE public.ad_reward_views
  ADD COLUMN IF NOT EXISTS reward_points integer CHECK (reward_points IS NULL OR reward_points >= 0),
  ADD COLUMN IF NOT EXISTS point_ledger_entry_id uuid REFERENCES public.point_ledger_entries(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS reward_session_id uuid REFERENCES public.ad_reward_sessions(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS legacy_grandfathered boolean NOT NULL DEFAULT false;

UPDATE public.ad_reward_views AS v
SET legacy_grandfathered = true
FROM public.ad_settings AS s
WHERE s.id = 1
  AND v.created_at < s.migration_cutover_at
  AND v.status = 'success'
  AND v.reward_amount > 0;

-- -----------------------------------------------------------------------------
-- Digital eligibility, immutable payment composition and cumulative refunds.
-- -----------------------------------------------------------------------------
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS is_points_eligible boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS max_points_coverage_percent integer NOT NULL DEFAULT 100
    CHECK (max_points_coverage_percent BETWEEN 0 AND 100);

CREATE OR REPLACE FUNCTION public.enforce_product_points_eligibility_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_is_privileged boolean :=
    COALESCE(
      NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
      NULLIF(current_setting('request.jwt.claim.role', true), ''),
      ''
    ) = 'service_role'
    OR (SELECT public.auth_is_admin());
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT v_is_privileged
       AND (NEW.is_points_eligible OR NEW.max_points_coverage_percent <> 100) THEN
      RAISE EXCEPTION 'POINT_ELIGIBILITY_ADMIN_REQUIRED' USING ERRCODE = '42501';
    END IF;
  ELSIF NOT v_is_privileged
        AND (NEW.is_points_eligible IS DISTINCT FROM OLD.is_points_eligible
          OR NEW.max_points_coverage_percent IS DISTINCT FROM OLD.max_points_coverage_percent) THEN
    RAISE EXCEPTION 'POINT_ELIGIBILITY_ADMIN_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF NEW.product_type IS DISTINCT FROM 'digital' THEN
    NEW.is_points_eligible := false;
    NEW.max_points_coverage_percent := 100;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER products_enforce_points_eligibility_admin
BEFORE INSERT OR UPDATE OF is_points_eligible, max_points_coverage_percent, product_type
ON public.products
FOR EACH ROW EXECUTE FUNCTION public.enforce_product_points_eligibility_admin();

ALTER TABLE public.digital_orders
  ADD COLUMN IF NOT EXISTS request_idempotency_key text,
  ADD COLUMN IF NOT EXISTS requested_use_points boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS gross_total_try numeric(12,2),
  ADD COLUMN IF NOT EXISTS points_spent bigint NOT NULL DEFAULT 0 CHECK (points_spent >= 0),
  ADD COLUMN IF NOT EXISTS points_per_try_snapshot integer,
  ADD COLUMN IF NOT EXISTS points_discount_try numeric(12,2) NOT NULL DEFAULT 0 CHECK (points_discount_try >= 0),
  ADD COLUMN IF NOT EXISTS cash_balance_paid_try numeric(12,2) NOT NULL DEFAULT 0 CHECK (cash_balance_paid_try >= 0),
  ADD COLUMN IF NOT EXISTS point_debit_entry_id uuid REFERENCES public.point_ledger_entries(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS payment_composition_version integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS refund_points_total bigint NOT NULL DEFAULT 0 CHECK (refund_points_total >= 0),
  ADD COLUMN IF NOT EXISTS refund_cash_total_try numeric(12,2) NOT NULL DEFAULT 0 CHECK (refund_cash_total_try >= 0),
  ADD COLUMN IF NOT EXISTS refund_gross_total_try numeric(12,2) NOT NULL DEFAULT 0 CHECK (refund_gross_total_try >= 0),
  ADD COLUMN IF NOT EXISTS reconciliation_status text NOT NULL DEFAULT 'not_required'
    CHECK (reconciliation_status IN ('not_required', 'pending_provider', 'reconciliation_pending', 'settled', 'refund_complete')),
  ADD COLUMN IF NOT EXISTS seller_delivered_ratio numeric(9,6)
    CHECK (seller_delivered_ratio IS NULL OR (seller_delivered_ratio > 0 AND seller_delivered_ratio <= 1));

UPDATE public.digital_orders
SET gross_total_try = total_price,
    cash_balance_paid_try = total_price,
    points_per_try_snapshot = 100,
    reconciliation_status = CASE
      WHEN status::text IN ('pending', 'in_progress') THEN 'pending_provider'
      ELSE 'settled'
    END
WHERE gross_total_try IS NULL;

ALTER TABLE public.digital_orders
  ALTER COLUMN gross_total_try SET NOT NULL,
  ALTER COLUMN points_per_try_snapshot SET NOT NULL;

CREATE UNIQUE INDEX digital_orders_request_idempotency_idx
  ON public.digital_orders(user_id, request_idempotency_key)
  WHERE request_idempotency_key IS NOT NULL;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conname = 'digital_orders_payment_composition_check'
      AND conrelid = 'public.digital_orders'::regclass
  ) THEN
    ALTER TABLE public.digital_orders ADD CONSTRAINT digital_orders_payment_composition_check CHECK (
      gross_total_try = points_discount_try + cash_balance_paid_try
      AND points_per_try_snapshot > 0
      AND ((points_spent = 0 AND points_discount_try = 0 AND point_debit_entry_id IS NULL)
           OR (points_spent > 0 AND points_discount_try > 0 AND point_debit_entry_id IS NOT NULL))
      AND refund_points_total <= points_spent
      AND refund_cash_total_try <= cash_balance_paid_try
      AND refund_gross_total_try <= gross_total_try
    ) NOT VALID;
  END IF;
END
$migration$;

CREATE TABLE public.digital_order_refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  digital_order_id uuid NOT NULL REFERENCES public.digital_orders(id) ON DELETE RESTRICT,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 200),
  requested_cumulative_gross_try numeric(12,2) NOT NULL CHECK (requested_cumulative_gross_try > 0),
  points_refunded bigint NOT NULL CHECK (points_refunded >= 0),
  cash_refunded_try numeric(12,2) NOT NULL CHECK (cash_refunded_try >= 0),
  point_ledger_entry_id uuid REFERENCES public.point_ledger_entries(id) ON DELETE RESTRICT,
  cash_balance_transaction_id uuid REFERENCES public.balance_transactions(id) ON DELETE RESTRICT,
  reason text NOT NULL CHECK (length(reason) BETWEEN 3 AND 1000),
  is_final boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (digital_order_id, idempotency_key),
  CHECK ((points_refunded = 0) = (point_ledger_entry_id IS NULL)),
  CHECK ((cash_refunded_try = 0) = (cash_balance_transaction_id IS NULL))
);

-- -----------------------------------------------------------------------------
-- Internal primitives. No direct EXECUTE grants; exposed RPCs call these as owner.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reward_points_apply_entry(
  p_user_id uuid,
  p_entry_type text,
  p_direction text,
  p_points bigint,
  p_reference_type text,
  p_reference_id uuid,
  p_idempotency_key text,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS public.point_ledger_entries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_account public.user_point_accounts%ROWTYPE;
  v_entry public.point_ledger_entries%ROWTYPE;
  v_after bigint;
BEGIN
  SELECT * INTO v_entry
  FROM public.point_ledger_entries AS le
  WHERE le.idempotency_key = p_idempotency_key;
  IF FOUND THEN
    IF v_entry.user_id IS DISTINCT FROM p_user_id
       OR v_entry.entry_type IS DISTINCT FROM p_entry_type
       OR v_entry.direction IS DISTINCT FROM p_direction
       OR v_entry.reference_type IS DISTINCT FROM p_reference_type
       OR v_entry.points IS DISTINCT FROM p_points
       OR v_entry.reference_id IS DISTINCT FROM p_reference_id
       OR v_entry.metadata IS DISTINCT FROM COALESCE(p_metadata, '{}'::jsonb) THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE = '23505';
    END IF;
    RETURN v_entry;
  END IF;

  IF p_points IS NULL OR p_points <= 0 THEN
    RAISE EXCEPTION 'INVALID_POINTS' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.user_point_accounts(user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO v_account
  FROM public.user_point_accounts AS a
  WHERE a.user_id = p_user_id
  FOR UPDATE;

  v_after := CASE WHEN p_direction = 'credit'
    THEN v_account.balance_points + p_points
    ELSE v_account.balance_points - p_points END;
  IF v_after < 0 THEN
    RAISE EXCEPTION 'INSUFFICIENT_POINTS' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.point_ledger_entries (
    user_id, entry_type, direction, points, balance_before_points,
    balance_after_points, reference_type, reference_id, idempotency_key, metadata
  ) VALUES (
    p_user_id, p_entry_type, p_direction, p_points, v_account.balance_points,
    v_after, p_reference_type, p_reference_id, p_idempotency_key, COALESCE(p_metadata, '{}'::jsonb)
  ) RETURNING * INTO v_entry;

  UPDATE public.user_point_accounts AS a
  SET balance_points = v_after,
      lifetime_earned_points = a.lifetime_earned_points
        + CASE WHEN p_entry_type IN ('ad_reward_credit', 'admin_correction_credit') THEN p_points ELSE 0 END,
      lifetime_spent_points = a.lifetime_spent_points
        + CASE WHEN p_entry_type IN ('digital_order_debit', 'admin_correction_debit', 'expiry_debit') THEN p_points ELSE 0 END,
      lifetime_refunded_points = a.lifetime_refunded_points
        + CASE WHEN p_entry_type = 'digital_order_refund' THEN p_points ELSE 0 END,
      version = a.version + 1,
      updated_at = clock_timestamp()
  WHERE a.user_id = p_user_id;

  RETURN v_entry;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_ad_reward_session(
  p_user_id uuid,
  p_nonce_hash text,
  p_client_idempotency_key text,
  p_device_pseudonym_hash text DEFAULT NULL,
  p_network_pseudonym_hash text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_session public.ad_reward_sessions%ROWTYPE;
  v_settings public.ad_settings%ROWTYPE;
BEGIN
  IF COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    ''
  ) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF p_nonce_hash IS NULL OR lower(p_nonce_hash) !~ '^[0-9a-f]{64}$'
     OR p_client_idempotency_key IS NULL
     OR length(p_client_idempotency_key) NOT BETWEEN 8 AND 200 THEN
    RAISE EXCEPTION 'INVALID_REWARD_SESSION_INPUT' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_settings FROM public.ad_settings AS s WHERE s.id = 1;
  IF NOT v_settings.reward_points_schema_ready OR v_settings.reward_feature_mode = 'disabled' THEN
    RAISE EXCEPTION 'REWARD_FEATURE_DISABLED' USING ERRCODE = '55000';
  END IF;
  IF v_settings.test_mode
     OR NOT v_settings.reward_points_earn_enabled
     OR NOT v_settings.reward_points_ssv_required
     OR NOT v_settings.reward_points_ssv_enabled
     OR NOT v_settings.legacy_ad_tl_grant_disabled
     OR v_settings.reward_feature_mode <> 'enabled' THEN
    RAISE EXCEPTION 'REWARD_EARN_NOT_READY' USING ERRCODE = '55000';
  END IF;
  INSERT INTO public.ad_reward_sessions (
    user_id, custom_data_nonce_hash, client_idempotency_key,
    device_pseudonym_hash, network_pseudonym_hash, status, expires_at,
    reward_points_snapshot, policy_version
  ) VALUES (
    p_user_id, lower(p_nonce_hash), p_client_idempotency_key,
    lower(p_device_pseudonym_hash), lower(p_network_pseudonym_hash), 'pending_ssv',
    clock_timestamp() + interval '30 minutes', v_settings.reward_min_points,
    v_settings.reward_policy_version
  )
  ON CONFLICT (user_id, client_idempotency_key) DO UPDATE
    SET client_idempotency_key = EXCLUDED.client_idempotency_key
  RETURNING * INTO v_session;
  IF v_session.custom_data_nonce_hash IS DISTINCT FROM lower(p_nonce_hash) THEN
    RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE = '23505';
  END IF;
  RETURN jsonb_build_object('reward_session_id', v_session.id, 'status', v_session.status,
    'expires_at', v_session.expires_at, 'policy_version', v_session.policy_version);
END;
$$;

CREATE OR REPLACE FUNCTION public.grant_verified_ad_points(
  p_reward_session_id uuid,
  p_provider_transaction_id text,
  p_provider_transaction_hash text,
  p_ad_unit_id text,
  p_signature_key_id text,
  p_callback_timestamp timestamptz,
  p_custom_data_nonce_hash text,
  p_provider_user_id_hash text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
  IF p_ad_unit_id IS DISTINCT FROM v_settings.admob_rewarded_unit_id_android
     AND p_ad_unit_id IS DISTINCT FROM v_settings.admob_rewarded_unit_id_ios THEN
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
$$;

CREATE OR REPLACE FUNCTION public.create_digital_order_with_points(
  p_user_id uuid,
  p_product_id uuid,
  p_target_url text,
  p_quantity integer,
  p_idempotency_key text,
  p_use_points boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_product public.products%ROWTYPE;
  v_order public.digital_orders%ROWTYPE;
  v_settings public.ad_settings%ROWTYPE;
  v_account public.user_point_accounts%ROWTYPE;
  v_cash public.user_balances%ROWTYPE;
  v_point_entry public.point_ledger_entries%ROWTYPE;
  v_order_id uuid := gen_random_uuid();
  v_unit_price numeric(12,4);
  v_gross numeric(12,2);
  v_gross_cents bigint;
  v_discount_cents bigint := 0;
  v_points bigint := 0;
  v_cash_paid numeric(12,2);
  v_cash_before numeric(12,2);
  v_cash_after numeric(12,2);
  v_cash_tx uuid;
  v_existing_count integer;
  v_existing_service_id text;
  v_cash_found boolean := false;
BEGIN
  IF COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    ''
  ) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) NOT BETWEEN 8 AND 200
     OR p_target_url IS NULL OR length(trim(p_target_url)) = 0 OR length(p_target_url) > 2000
     OR p_use_points IS NULL THEN
    RAISE EXCEPTION 'INVALID_ORDER_INPUT' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':' || p_idempotency_key, 71002)
  );
  SELECT * INTO v_order FROM public.digital_orders AS o
  WHERE o.user_id = p_user_id AND o.request_idempotency_key = p_idempotency_key;
  IF FOUND THEN
    IF v_order.product_id IS DISTINCT FROM p_product_id
       OR v_order.target_url IS DISTINCT FROM trim(p_target_url)
       OR v_order.quantity IS DISTINCT FROM p_quantity
       OR v_order.requested_use_points IS DISTINCT FROM p_use_points THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE = '23505';
    END IF;
    SELECT p.smm_service_id INTO v_existing_service_id
    FROM public.products AS p WHERE p.id = v_order.product_id;
    RETURN jsonb_build_object('digital_order_id', v_order.id, 'provider_id', v_order.provider_id,
      'smm_service_id', v_existing_service_id,
      'gross_total_try', v_order.gross_total_try, 'points_spent', v_order.points_spent,
      'points_discount_try', v_order.points_discount_try, 'cash_paid_try', v_order.cash_balance_paid_try,
      'duplicate', true);
  END IF;

  SELECT * INTO v_product FROM public.products AS p
  WHERE p.id = p_product_id AND p.is_available = true;
  IF NOT FOUND OR v_product.product_type IS DISTINCT FROM 'digital'
     OR p_quantity IS NULL OR p_quantity < v_product.min_quantity OR p_quantity > v_product.max_quantity THEN
    RAISE EXCEPTION 'DIGITAL_PRODUCT_INVALID' USING ERRCODE = '22023';
  END IF;
  -- Different request idempotency keys for the same user/product must still
  -- serialize before evaluating max_orders_per_user.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':' || p_product_id::text, 71003)
  );
  IF v_product.max_orders_per_user IS NOT NULL THEN
    SELECT count(*) INTO v_existing_count FROM public.digital_orders AS o
    WHERE o.user_id = p_user_id AND o.product_id = p_product_id
      AND o.status::text NOT IN ('failed', 'refunded');
    IF v_existing_count >= v_product.max_orders_per_user THEN
      RAISE EXCEPTION 'DIGITAL_ORDER_LIMIT' USING ERRCODE = '54000';
    END IF;
  END IF;
  SELECT * INTO v_settings FROM public.ad_settings AS s WHERE s.id = 1;
  v_unit_price := round(v_product.price_per_1000 / 1000.0, 4);
  v_gross := round(v_unit_price * p_quantity, 2);
  v_gross_cents := round(v_gross * 100)::bigint;

  INSERT INTO public.user_point_accounts(user_id) VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_account FROM public.user_point_accounts AS a
  WHERE a.user_id = p_user_id FOR UPDATE;
  SELECT * INTO v_cash FROM public.user_balances AS b
  WHERE b.user_id = p_user_id FOR UPDATE;
  v_cash_found := FOUND;

  IF p_use_points AND v_settings.reward_points_spend_enabled
     AND v_settings.reward_points_eligible_products_enabled AND v_product.is_points_eligible THEN
    v_discount_cents := LEAST(
      floor(v_account.balance_points * 100.0 / v_settings.points_per_try)::bigint,
      floor(v_gross_cents * v_product.max_points_coverage_percent / 100.0)::bigint
    );
    v_points := (v_discount_cents * v_settings.points_per_try / 100)::bigint;
  END IF;
  v_cash_paid := round((v_gross_cents - v_discount_cents) / 100.0, 2);
  IF v_cash_paid > 0 AND (NOT v_cash_found OR v_cash.balance < v_cash_paid) THEN
    RAISE EXCEPTION 'INSUFFICIENT_COMBINED_BALANCE' USING ERRCODE = 'P0001';
  END IF;

  IF v_points > 0 THEN
    v_point_entry := public.reward_points_apply_entry(p_user_id, 'digital_order_debit', 'debit', v_points,
      'digital_order', v_order_id, 'digital-order-points:' || v_order_id,
      jsonb_build_object('points_per_try', v_settings.points_per_try, 'discount_cents', v_discount_cents));
  END IF;
  IF v_cash_paid > 0 THEN
    v_cash_before := v_cash.balance;
    v_cash_after := v_cash.balance - v_cash_paid;
    v_cash_tx := gen_random_uuid();
    UPDATE public.user_balances AS b SET balance = v_cash_after,
      total_spent = b.total_spent + v_cash_paid, updated_at = clock_timestamp() WHERE b.id = v_cash.id;
    INSERT INTO public.balance_transactions(id, user_id, type, amount, net_amount, balance_before, balance_after,
      reference_type, reference_id, status, description, payment_method, metadata)
    VALUES (v_cash_tx, p_user_id, 'order_payment', v_cash_paid, v_cash_paid, v_cash_before, v_cash_after,
      'digital_order', v_order_id, 'completed', 'Dijital sipariş TL bakiye bileşeni', 'balance',
      jsonb_build_object('composition_version', 1, 'points_are_not_cash', true));
  ELSE
    v_cash_after := COALESCE(v_cash.balance, 0);
  END IF;

  INSERT INTO public.digital_orders(id, user_id, product_id, provider_id, target_url, quantity,
    unit_price, total_price, status, balance_transaction_id, request_idempotency_key, requested_use_points,
    gross_total_try, points_spent, points_per_try_snapshot, points_discount_try,
    cash_balance_paid_try, point_debit_entry_id, payment_composition_version, reconciliation_status)
  VALUES (v_order_id, p_user_id, p_product_id, v_product.smm_provider_id, trim(p_target_url), p_quantity,
    v_unit_price, v_gross, 'pending', v_cash_tx, p_idempotency_key, p_use_points,
    v_gross, v_points, v_settings.points_per_try, v_discount_cents / 100.0,
    v_cash_paid, v_point_entry.id, 1, 'pending_provider') RETURNING * INTO v_order;

  RETURN jsonb_build_object('digital_order_id', v_order.id, 'provider_id', v_product.smm_provider_id,
    'smm_service_id', v_product.smm_service_id, 'gross_total_try', v_gross,
    'points_spent', v_points, 'points_discount_try', v_discount_cents / 100.0,
    'cash_paid_try', v_cash_paid, 'point_balance_after', COALESCE(v_point_entry.balance_after_points, v_account.balance_points),
    'cash_balance_after', v_cash_after, 'reconciliation_status', 'pending_provider', 'duplicate', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.refund_digital_order_payment(
  p_digital_order_id uuid,
  p_cumulative_refund_try numeric,
  p_idempotency_key text,
  p_reason text,
  p_is_final boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order public.digital_orders%ROWTYPE;
  v_existing public.digital_order_refunds%ROWTYPE;
  v_account public.user_point_accounts%ROWTYPE;
  v_cash public.user_balances%ROWTYPE;
  v_point_entry public.point_ledger_entries%ROWTYPE;
  v_target_cents bigint;
  v_point_discount_cents bigint;
  v_target_point_cents bigint;
  v_target_points bigint;
  v_target_cash numeric(12,2);
  v_delta_points bigint;
  v_delta_cash numeric(12,2);
  v_cash_tx uuid;
  v_refund_id uuid := gen_random_uuid();
  v_cash_found boolean := false;
BEGIN
  IF COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    ''
  ) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_order FROM public.digital_orders AS o WHERE o.id = p_digital_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DIGITAL_ORDER_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  -- Check idempotency after serializing on the order. A concurrent duplicate
  -- then observes the committed refund instead of failing the cumulative
  -- amount validation or the unique constraint.
  SELECT * INTO v_existing FROM public.digital_order_refunds AS r
  WHERE r.digital_order_id = p_digital_order_id AND r.idempotency_key = p_idempotency_key;
  IF FOUND THEN
    IF v_existing.requested_cumulative_gross_try IS DISTINCT FROM p_cumulative_refund_try
       OR v_existing.reason IS DISTINCT FROM p_reason
       OR v_existing.is_final IS DISTINCT FROM p_is_final THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE = '23505';
    END IF;
    RETURN jsonb_build_object('refund_id', v_existing.id, 'points_refunded', v_existing.points_refunded,
      'cash_refunded_try', v_existing.cash_refunded_try, 'duplicate', true);
  END IF;
  IF v_order.seller_credited THEN
    RAISE EXCEPTION 'SELLER_ALREADY_CREDITED_REFUND_REQUIRES_REVERSAL'
      USING ERRCODE = '55000';
  END IF;
  -- Only service-role workers can call this RPC. They must establish a
  -- definitive provider/manual outcome before calling it; keeping the refund
  -- transaction independent from a prior state write prevents lost refunds.
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) NOT BETWEEN 8 AND 200
     OR p_reason IS NULL OR length(p_reason) NOT BETWEEN 3 AND 1000
     OR p_is_final IS NULL THEN
    RAISE EXCEPTION 'INVALID_REFUND_INPUT' USING ERRCODE = '22023';
  END IF;
  IF p_cumulative_refund_try IS NULL OR p_cumulative_refund_try <= v_order.refund_gross_total_try
     OR p_cumulative_refund_try > v_order.gross_total_try
     OR p_cumulative_refund_try IS DISTINCT FROM round(p_cumulative_refund_try, 2) THEN
    RAISE EXCEPTION 'INVALID_CUMULATIVE_REFUND' USING ERRCODE = '22023';
  END IF;
  IF p_is_final AND p_cumulative_refund_try IS DISTINCT FROM v_order.gross_total_try THEN
    RAISE EXCEPTION 'FINAL_REFUND_MUST_CLOSE_REMAINDER' USING ERRCODE = '22023';
  END IF;

  -- Point account is always locked before cash account, matching checkout.
  INSERT INTO public.user_point_accounts(user_id) VALUES (v_order.user_id) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_account FROM public.user_point_accounts AS a WHERE a.user_id = v_order.user_id FOR UPDATE;
  SELECT * INTO v_cash FROM public.user_balances AS b WHERE b.user_id = v_order.user_id FOR UPDATE;
  v_cash_found := FOUND;

  v_target_cents := round(p_cumulative_refund_try * 100)::bigint;
  v_point_discount_cents := round(v_order.points_discount_try * 100)::bigint;
  v_target_point_cents := LEAST(v_target_cents, v_point_discount_cents);
  v_target_points := CASE
    WHEN v_point_discount_cents = 0 THEN 0
    WHEN v_target_point_cents = v_point_discount_cents THEN v_order.points_spent
    ELSE floor(v_order.points_spent * v_target_point_cents::numeric / v_point_discount_cents)::bigint
  END;
  v_target_cash := round(GREATEST(v_target_cents - v_point_discount_cents, 0) / 100.0, 2);
  v_target_cash := LEAST(v_target_cash, v_order.cash_balance_paid_try);
  v_delta_points := v_target_points - v_order.refund_points_total;
  v_delta_cash := v_target_cash - v_order.refund_cash_total_try;

  IF v_delta_cash > 0 AND NOT v_cash_found THEN
    RAISE EXCEPTION 'CASH_ACCOUNT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_delta_points > 0 THEN
    v_point_entry := public.reward_points_apply_entry(v_order.user_id, 'digital_order_refund', 'credit', v_delta_points,
      'digital_order', v_order.id, 'digital-refund-points:' || v_refund_id,
      jsonb_build_object('cumulative_refund_try', p_cumulative_refund_try, 'source', 'points'));
  END IF;
  IF v_delta_cash > 0 THEN
    v_cash_tx := gen_random_uuid();
    UPDATE public.user_balances AS b SET balance = b.balance + v_delta_cash,
      total_refunds = b.total_refunds + v_delta_cash, updated_at = clock_timestamp()
      WHERE b.id = v_cash.id;
    INSERT INTO public.balance_transactions(id, user_id, type, amount, net_amount, balance_before, balance_after,
      reference_type, reference_id, status, description, payment_method, metadata)
    VALUES (v_cash_tx, v_order.user_id, 'refund', v_delta_cash, v_delta_cash, v_cash.balance, v_cash.balance + v_delta_cash,
      'digital_order_refund', v_refund_id, 'completed', 'Dijital sipariş TL kaynağına iade', 'balance',
      jsonb_build_object('digital_order_id', v_order.id, 'source', 'cash_balance'));
  END IF;

  INSERT INTO public.digital_order_refunds(id, digital_order_id, idempotency_key,
    requested_cumulative_gross_try, points_refunded, cash_refunded_try,
    point_ledger_entry_id, cash_balance_transaction_id, reason, is_final)
  VALUES (v_refund_id, v_order.id, p_idempotency_key, p_cumulative_refund_try,
    v_delta_points, v_delta_cash, v_point_entry.id, v_cash_tx, p_reason, p_is_final);
  UPDATE public.digital_orders SET refund_points_total = v_target_points,
    refund_cash_total_try = v_target_cash, refund_gross_total_try = p_cumulative_refund_try,
    reconciliation_status = CASE WHEN p_is_final OR p_cumulative_refund_try = gross_total_try
      THEN 'refund_complete' ELSE reconciliation_status END
  WHERE id = v_order.id;

  RETURN jsonb_build_object('refund_id', v_refund_id, 'points_refunded', v_delta_points,
    'cash_refunded_try', v_delta_cash, 'cumulative_points_refunded', v_target_points,
    'cumulative_cash_refunded_try', v_target_cash, 'duplicate', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_digital_order_reconciliation(
  p_digital_order_id uuid, p_state text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_current text;
BEGIN
  IF COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    ''
  ) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF p_state NOT IN ('pending_provider', 'reconciliation_pending', 'settled') THEN
    RAISE EXCEPTION 'INVALID_RECONCILIATION_STATE' USING ERRCODE = '22023';
  END IF;
  SELECT reconciliation_status INTO v_current
  FROM public.digital_orders WHERE id = p_digital_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DIGITAL_ORDER_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_current = 'refund_complete' THEN
    RAISE EXCEPTION 'ORDER_PAYMENT_ALREADY_REFUNDED' USING ERRCODE = '55000';
  END IF;
  IF v_current = 'settled' AND p_state <> 'settled' THEN
    RAISE EXCEPTION 'RECONCILIATION_STATE_REGRESSION' USING ERRCODE = '55000';
  END IF;
  UPDATE public.digital_orders SET reconciliation_status = p_state, updated_at = clock_timestamp()
  WHERE id = p_digital_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.credit_digital_order_seller(
  p_digital_order_id uuid,
  p_delivered_ratio numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order public.digital_orders%ROWTYPE;
  v_seller_id uuid;
  v_product_name text;
  v_commission_rate numeric(5,2);
  v_gross numeric(12,2);
  v_commission numeric(12,2);
  v_net numeric(12,2);
  v_normalized_ratio numeric(9,6);
  v_expected_refund numeric(12,2);
  v_balance public.user_balances%ROWTYPE;
  v_after numeric(12,2);
  v_transaction_id uuid;
BEGIN
  IF COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    ''
  ) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF p_delivered_ratio IS NULL OR p_delivered_ratio <= 0 OR p_delivered_ratio > 1 THEN
    RAISE EXCEPTION 'INVALID_DELIVERED_RATIO' USING ERRCODE = '22023';
  END IF;
  v_normalized_ratio := round(p_delivered_ratio, 6);
  SELECT * INTO v_order
  FROM public.digital_orders AS o
  WHERE o.id = p_digital_order_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DIGITAL_ORDER_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_order.seller_credited THEN
    IF v_order.seller_delivered_ratio IS DISTINCT FROM v_normalized_ratio THEN
      RAISE EXCEPTION 'SELLER_CREDIT_IDEMPOTENCY_CONFLICT' USING ERRCODE = '23505';
    END IF;
    RETURN jsonb_build_object('duplicate', true,
      'commission_amount', v_order.commission_amount,
      'net_seller_amount', v_order.net_seller_amount);
  END IF;
  IF v_order.reconciliation_status IS DISTINCT FROM 'settled' THEN
    RAISE EXCEPTION 'ORDER_RECONCILIATION_NOT_SETTLED' USING ERRCODE = '55000';
  END IF;
  v_expected_refund := round(v_order.gross_total_try * (1 - p_delivered_ratio), 2);
  IF v_order.refund_gross_total_try IS DISTINCT FROM v_expected_refund THEN
    RAISE EXCEPTION 'DELIVERY_REFUND_COMPOSITION_MISMATCH' USING ERRCODE = '22023';
  END IF;

  SELECT s.owner_id, p.name, COALESCE(s.digital_commission_rate, 10)
  INTO v_seller_id, v_product_name, v_commission_rate
  FROM public.products AS p
  JOIN public.shops AS s ON s.id = p.shop_id
  WHERE p.id = v_order.product_id;
  IF v_seller_id IS NULL THEN RAISE EXCEPTION 'DIGITAL_SELLER_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_commission_rate < 0 OR v_commission_rate > 100 THEN
    RAISE EXCEPTION 'INVALID_DIGITAL_COMMISSION_RATE' USING ERRCODE = '22023';
  END IF;

  -- Derive delivered gross from the persisted refund snapshot so seller credit
  -- plus customer refund can never exceed the immutable order gross.
  v_gross := v_order.gross_total_try - v_order.refund_gross_total_try;
  v_commission := round(v_gross * v_commission_rate / 100, 2);
  v_net := v_gross - v_commission;
  IF v_net > 0 THEN
    INSERT INTO public.user_balances(user_id) VALUES (v_seller_id)
    ON CONFLICT (user_id) DO NOTHING;
    SELECT * INTO v_balance FROM public.user_balances AS b
    WHERE b.user_id = v_seller_id FOR UPDATE;
    v_after := v_balance.balance + v_net;
    UPDATE public.user_balances AS b
    SET balance = v_after, total_earned = b.total_earned + v_net,
        updated_at = clock_timestamp()
    WHERE b.id = v_balance.id;
    v_transaction_id := gen_random_uuid();
    INSERT INTO public.balance_transactions(
      id, user_id, type, amount, net_amount, balance_before, balance_after,
      reference_type, reference_id, status, description, payment_method, metadata
    ) VALUES (
      v_transaction_id, v_seller_id, 'commission', v_net, v_net, v_balance.balance, v_after,
      'digital_order', v_order.id, 'completed',
      'Dijital ürün satışı kazancı - ' || v_product_name, 'balance',
      jsonb_build_object('gross_delivered_try', v_gross,
        'commission_rate', v_commission_rate, 'points_are_platform_discount', true)
    );
  END IF;
  UPDATE public.digital_orders
  SET seller_credited = true, seller_delivered_ratio = v_normalized_ratio,
      commission_amount = v_commission, net_seller_amount = v_net,
      updated_at = clock_timestamp()
  WHERE id = v_order.id;
  RETURN jsonb_build_object('duplicate', false, 'transaction_id', v_transaction_id,
    'commission_amount', v_commission, 'net_seller_amount', v_net);
END;
$$;

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
  p_reason text
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
     OR p_reason IS NULL
     OR p_reward_min_points <= 0 OR p_reward_max_points <> p_reward_min_points
     OR p_max_daily_reward_points < 0 OR p_points_per_try <= 0
     OR p_points_per_try % 100 <> 0
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
    reward_policy_version = reward_policy_version + 1,
    legacy_ad_tl_grant_disabled = true, is_enabled = false, updated_at = clock_timestamp()
  WHERE s.id = 1 RETURNING to_jsonb(s) INTO v_new;
  INSERT INTO public.reward_points_config_audit(admin_user_id, old_config, new_config, reason)
  VALUES (v_admin, v_old, v_new, p_reason);
  RETURN jsonb_build_object(
    'id', v_new -> 'id',
    'test_mode', v_new -> 'test_mode',
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

CREATE OR REPLACE FUNCTION public.purge_expired_reward_fraud_hashes(p_limit integer DEFAULT 1000)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_count integer;
  v_session_count integer;
BEGIN
  IF COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    ''
  ) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING ERRCODE = '42501';
  END IF;
  WITH expired AS (
    SELECT e.id FROM public.ad_reward_ssv_events AS e
    WHERE e.retention_expires_at < clock_timestamp() ORDER BY e.retention_expires_at LIMIT p_limit
  )
  UPDATE public.ad_reward_ssv_events AS e SET provider_user_id_hash = NULL
  FROM expired WHERE e.id = expired.id AND e.provider_user_id_hash IS NOT NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  WITH expired_sessions AS (
    SELECT rs.id
    FROM public.ad_reward_sessions AS rs
    CROSS JOIN public.ad_settings AS s
    WHERE s.id = 1
      AND rs.created_at < clock_timestamp() - make_interval(days => s.fraud_hash_retention_days)
      AND (rs.device_pseudonym_hash IS NOT NULL OR rs.network_pseudonym_hash IS NOT NULL)
    ORDER BY rs.created_at
    LIMIT p_limit
  )
  UPDATE public.ad_reward_sessions AS rs
  SET device_pseudonym_hash = NULL, network_pseudonym_hash = NULL, updated_at = clock_timestamp()
  FROM expired_sessions WHERE rs.id = expired_sessions.id;
  GET DIAGNOSTICS v_session_count = ROW_COUNT;
  RETURN v_count + v_session_count;
END;
$$;

-- -----------------------------------------------------------------------------
-- Safe read surfaces, RLS and least privilege ACL.
-- -----------------------------------------------------------------------------
CREATE VIEW public.reward_points_public_config
WITH (security_invoker = true) AS
SELECT id, test_mode, reward_min_points, reward_max_points,
  max_daily_reward_points, points_per_try, reward_policy_version,
  reward_feature_mode, reward_points_schema_ready, reward_points_earn_enabled,
  reward_points_ssv_required, reward_points_ssv_enabled,
  reward_points_spend_enabled, reward_points_eligible_products_enabled,
  reward_points_admin_reporting_enabled, legacy_ad_tl_grant_disabled,
  max_views_per_day, max_views_per_hour, cooldown_seconds
FROM public.ad_settings WHERE id = 1;

CREATE VIEW public.my_point_ledger_entries
WITH (security_invoker = true) AS
SELECT id, user_id, entry_type, direction, points,
  balance_before_points, balance_after_points,
  reference_type, reference_id, created_at
FROM public.point_ledger_entries;

CREATE VIEW public.my_ad_reward_sessions
WITH (security_invoker = true) AS
SELECT id, user_id, status, expires_at, credited_points, policy_version, created_at, updated_at
FROM public.ad_reward_sessions;

ALTER TABLE public.user_point_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.point_ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_reward_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_reward_ssv_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_reward_daily_budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reward_points_config_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reward_points_migration_audits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.digital_order_refunds ENABLE ROW LEVEL SECURITY;

-- SECURITY DEFINER functions execute as reward_points_owner. Explicit table
-- grants alone do not bypass RLS on pre-existing application tables, so these
-- narrowly scoped policies are required for the internal transaction paths.
CREATE POLICY reward_points_owner_profiles_select ON public.profiles
FOR SELECT TO reward_points_owner USING (true);
CREATE POLICY reward_points_owner_products_select ON public.products
FOR SELECT TO reward_points_owner USING (true);
CREATE POLICY reward_points_owner_shops_select ON public.shops
FOR SELECT TO reward_points_owner USING (true);
CREATE POLICY reward_points_owner_ad_settings_select ON public.ad_settings
FOR SELECT TO reward_points_owner USING (true);
CREATE POLICY reward_points_owner_ad_settings_update ON public.ad_settings
FOR UPDATE TO reward_points_owner USING (true) WITH CHECK (true);
CREATE POLICY reward_points_owner_user_balances_select ON public.user_balances
FOR SELECT TO reward_points_owner USING (true);
CREATE POLICY reward_points_owner_user_balances_update ON public.user_balances
FOR UPDATE TO reward_points_owner USING (true) WITH CHECK (true);
CREATE POLICY reward_points_owner_user_balances_insert ON public.user_balances
FOR INSERT TO reward_points_owner WITH CHECK (true);
CREATE POLICY reward_points_owner_digital_orders_select ON public.digital_orders
FOR SELECT TO reward_points_owner USING (true);
CREATE POLICY reward_points_owner_digital_orders_insert ON public.digital_orders
FOR INSERT TO reward_points_owner WITH CHECK (true);
CREATE POLICY reward_points_owner_digital_orders_update ON public.digital_orders
FOR UPDATE TO reward_points_owner USING (true) WITH CHECK (true);
CREATE POLICY reward_points_owner_balance_transactions_insert ON public.balance_transactions
FOR INSERT TO reward_points_owner WITH CHECK (true);

CREATE POLICY user_point_accounts_select_own ON public.user_point_accounts
FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY point_ledger_entries_select_own ON public.point_ledger_entries
FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY ad_reward_sessions_select_own ON public.ad_reward_sessions
FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY ad_reward_sessions_select_admin ON public.ad_reward_sessions
FOR SELECT TO authenticated USING ((SELECT public.auth_is_admin()));
CREATE POLICY digital_order_refunds_select_own ON public.digital_order_refunds
FOR SELECT TO authenticated USING (EXISTS (
  SELECT 1 FROM public.digital_orders AS o
  WHERE o.id = digital_order_id AND o.user_id = (SELECT auth.uid())
));

REVOKE ALL ON public.user_point_accounts, public.point_ledger_entries,
  public.ad_reward_sessions, public.ad_reward_ssv_events, public.ad_reward_daily_budgets,
  public.reward_points_config_audit, public.reward_points_migration_audits,
  public.digital_order_refunds FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.user_point_accounts, public.digital_order_refunds TO authenticated;
GRANT SELECT (id, user_id, entry_type, direction, points,
  balance_before_points, balance_after_points, reference_type, reference_id,
  created_at) ON public.point_ledger_entries TO authenticated;
GRANT SELECT (id, user_id, status, expires_at, credited_points, policy_version,
  credited_at, created_at, updated_at) ON public.ad_reward_sessions TO authenticated;
REVOKE ALL ON public.ad_reward_views FROM anon, authenticated;
REVOKE ALL ON public.ad_settings FROM anon, authenticated;
GRANT SELECT (id, test_mode, reward_min_points, reward_max_points,
  max_daily_reward_points, points_per_try, reward_policy_version,
  reward_feature_mode, reward_points_schema_ready, reward_points_earn_enabled,
  reward_points_ssv_required, reward_points_ssv_enabled,
  reward_points_spend_enabled, reward_points_eligible_products_enabled,
  reward_points_admin_reporting_enabled, legacy_ad_tl_grant_disabled,
  max_views_per_day, max_views_per_hour, cooldown_seconds)
  ON public.ad_settings TO authenticated;
GRANT SELECT ON public.reward_points_public_config, public.my_ad_reward_sessions,
  public.my_point_ledger_entries TO authenticated;

REVOKE ALL ON FUNCTION public.reward_points_apply_entry(uuid,text,text,bigint,text,uuid,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.reject_point_ledger_mutation() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_ad_reward_session(uuid,text,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_digital_order_with_points(uuid,uuid,text,integer,text,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refund_digital_order_payment(uuid,numeric,text,text,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_digital_order_reconciliation(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.credit_digital_order_seller(uuid,numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.purge_expired_reward_fraud_hashes(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_ad_reward_session(uuid,text,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_digital_order_with_points(uuid,uuid,text,integer,text,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.refund_digital_order_payment(uuid,numeric,text,text,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_digital_order_reconciliation(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.credit_digital_order_seller(uuid,numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.purge_expired_reward_fraud_hashes(integer) TO service_role;
REVOKE ALL ON FUNCTION public.admin_update_reward_points_config(integer,integer,bigint,integer,boolean,text,boolean,boolean,boolean,boolean,text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.admin_update_reward_points_config(integer,integer,bigint,integer,boolean,text,boolean,boolean,boolean,boolean,text) TO authenticated;

-- Legacy cash-reward RPC remains as a compatibility signature but can never credit.
-- Eski grant_ad_reward isimli parametrelerle (p_user_id, ...) yaratıldığı için
-- CREATE OR REPLACE parametre adını değiştiremez; önce DROP gerekir (42P13).
DROP FUNCTION IF EXISTS public.grant_ad_reward(uuid,text,text,integer);
CREATE OR REPLACE FUNCTION public.grant_ad_reward(uuid,text,text,integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN jsonb_build_object('status', 410, 'error_code', 'LEGACY_AD_TL_GRANT_DISABLED');
END;
$$;
REVOKE ALL ON FUNCTION public.grant_ad_reward(uuid,text,text,integer) FROM PUBLIC, anon, authenticated, service_role;

-- The old checkout signature cannot consume points and is closed during cutover.
REVOKE ALL ON FUNCTION public.create_digital_order(uuid,uuid,text,integer) FROM PUBLIC, anon, authenticated, service_role;

-- Remove direct admin config writes; validated RPC is the only client mutation path.
DROP POLICY IF EXISTS "ad_settings_admin_all" ON public.ad_settings;
DROP POLICY IF EXISTS "ad_reward_views_admin_select" ON public.ad_reward_views;
DROP POLICY IF EXISTS "ad_reward_views_select_own" ON public.ad_reward_views;

ALTER TABLE public.user_point_accounts OWNER TO reward_points_owner;
ALTER TABLE public.point_ledger_entries OWNER TO reward_points_owner;
ALTER TABLE public.ad_reward_sessions OWNER TO reward_points_owner;
ALTER TABLE public.ad_reward_ssv_events OWNER TO reward_points_owner;
ALTER TABLE public.ad_reward_daily_budgets OWNER TO reward_points_owner;
ALTER TABLE public.reward_points_config_audit OWNER TO reward_points_owner;
ALTER TABLE public.reward_points_migration_audits OWNER TO reward_points_owner;
ALTER TABLE public.digital_order_refunds OWNER TO reward_points_owner;
ALTER FUNCTION public.reward_points_apply_entry(uuid,text,text,bigint,text,uuid,text,jsonb) OWNER TO reward_points_owner;
ALTER FUNCTION public.reject_point_ledger_mutation() OWNER TO reward_points_owner;
ALTER FUNCTION public.create_ad_reward_session(uuid,text,text,text,text) OWNER TO reward_points_owner;
ALTER FUNCTION public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text) OWNER TO reward_points_owner;
ALTER FUNCTION public.create_digital_order_with_points(uuid,uuid,text,integer,text,boolean) OWNER TO reward_points_owner;
ALTER FUNCTION public.refund_digital_order_payment(uuid,numeric,text,text,boolean) OWNER TO reward_points_owner;
ALTER FUNCTION public.set_digital_order_reconciliation(uuid,text) OWNER TO reward_points_owner;
ALTER FUNCTION public.credit_digital_order_seller(uuid,numeric) OWNER TO reward_points_owner;
ALTER FUNCTION public.admin_update_reward_points_config(integer,integer,bigint,integer,boolean,text,boolean,boolean,boolean,boolean,text) OWNER TO reward_points_owner;
ALTER FUNCTION public.purge_expired_reward_fraud_hashes(integer) OWNER TO reward_points_owner;
ALTER FUNCTION public.enforce_product_points_eligibility_admin() OWNER TO reward_points_owner;

GRANT USAGE ON SCHEMA public, auth TO reward_points_owner;
GRANT SELECT ON public.profiles, public.products, public.shops TO reward_points_owner;
GRANT SELECT, INSERT, UPDATE ON public.user_balances TO reward_points_owner;
GRANT SELECT, UPDATE ON public.ad_settings TO reward_points_owner;
GRANT SELECT, INSERT, UPDATE ON public.digital_orders TO reward_points_owner;
GRANT INSERT ON public.balance_transactions TO reward_points_owner;
GRANT USAGE ON TYPE public.balance_transaction_type, public.balance_transaction_status,
  public.digital_order_status TO reward_points_owner;
GRANT EXECUTE ON FUNCTION auth.uid() TO reward_points_owner;
GRANT EXECUTE ON FUNCTION public.auth_is_admin() TO reward_points_owner;
REVOKE CREATE ON SCHEMA public FROM PUBLIC, reward_points_owner;

COMMENT ON TABLE public.point_ledger_entries IS 'Append-only non-cash reward point ledger. Points cannot be withdrawn, transferred, or used for physical goods.';
COMMENT ON COLUMN public.digital_orders.points_discount_try IS 'In-app digital discount snapshot only; not cash, receivable, or seller transfer value.';

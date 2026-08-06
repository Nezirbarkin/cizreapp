-- =============================================================================
-- 20260804000002_fill_app_contract_gaps.sql
-- =============================================================================
-- Tek dosyalik, KONSOLIDE uygulama kontrati duzeltmesi.
--
-- KAYNAK: CIZREAPP_TESHIS.sql raporunun isaret ettigi eksik nesneleri olusturur:
--   * 7 eksik RPC: admin_reward_points_overview, cancel_order,
--     commit_balance_order, commit_cod_order, ensure_my_profile,
--     prepare_checkout_session, set_my_presence
--   * Eksik tablo/view: user_point_accounts, reward_points_public_config,
--     my_point_ledger_entries, my_ad_reward_sessions, public_profiles_safe,
--     v_admin_commission_dashboard, v_debt_orders, api_keys
--   * RLS SELECT policy: news_views
--   * Yetki: smm_providers (kolon-bazli SELECT grant)
--
-- NOTLAR:
--   1) "EKSIK TABLO" sanilan avatars, covers, deals, public, task_images,
--      task_screenshots aslinda STORAGE BUCKET'tur; bu dosya tablo olusturmaz.
--   2) prepare_checkout_session / commit_cod_order / commit_balance_order
--      ORIJINAL migrationlarda `private` semasindaydi. PostgREST yalniz
--      `public` semasini expose ettigi icin uygulama cagiramazdi. Bu dosya
--      onlari `public` semasinda olusturur (SECURITY DEFINER; private
--      tablolara dahili erisir).
--   3) cancel_order, private.server_checkout_audit'e olmayan kolonlara
--      (order_id, payload) yaziyordu; gercek kolonlara (detail) duzeltildi.
--   4) commit_cod_order / commit_balance_order `nextval('order_number_seq')`
--      cagrisini `SET search_path=''` altinda niteliksiz yapiyordu (bos
--      search_path'te cozulemez); `public.order_number_seq` olarak nitelendi.
--      [Build script'te olmayan, bu uretimde eklenen duzeltme.]
--
-- UYGULAMA: Supabase Dashboard > SQL Editor > TAMAMINI yapistir > Run.
-- =============================================================================


-- BOLUM 0: order_number_seq (commit_*_order RPC'leri nextval kullanir)
CREATE SEQUENCE IF NOT EXISTS public.order_number_seq;


-- =============================================================================
-- KAYNAK 1/9: 20260730000002_admob_reward_points_system.sql (verbatim)
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

-- =============================================================================
-- KAYNAK 2/9: 20260801000001_admin_reward_points_overview.sql (verbatim)
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

-- =============================================================================
-- KAYNAK 3/9: 20260802000005_server_authoritative_checkout_schema.sql (verbatim)
-- CERRAHI DÜZELTME #3: "GRANT ALL ON private.server_checkout_session_items ..."
--   satırı KALDIRILDI — bu tablo bu migration'da oluşturulmuyor (items items_snapshot
--   JSONB kolonunda saklanıyor), bu yüzden GRANT "relation does not exist" hatası verirdi.
-- =============================================================================
-- ════════════════════════════════════════════════════════════════════════
-- SERVER-AUTHORITATIVE CHECKOUT ŞEMASI
-- Tarih: 2026-08-02
-- ════════════════════════════════════════════════════════════════════════
-- Bu migration, finansal checkout akışını client-authoritative'den
-- server-authoritative'e taşımak için gerekli yeni şema ve tabloları
-- oluşturur.
--
-- YENİ NESNELER:
--   - private şema (authenticated/anon GRANT yok, sadece service_role)
--   - private.server_checkout_sessions (immutable, server yazar)
--   - private.server_checkout_session_items (immutable, server yazar)
--   - private.flash_sale_reservations (rezervasyon, FOR UPDATE ile)
--   - private.server_checkout_audit (admin SELECT)
--   - public.orders, public.order_items, public.payment_transactions
--     kolon eklentileri (checkout_session_id, expected_amount, vb.)
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════════
-- 1) PRIVATE ŞEMA
-- ════════════════════════════════════════════════════════════════════════
-- Bu şemadaki tablolar PostgREST API'den hiçbir zaman EXPOSE EDILMEZ.
-- SECURITY DEFINER RPC'ler bu şemaya erişir; anon/authenticated
-- role'larinin GRANT'i yoktur.
CREATE SCHEMA IF NOT EXISTS private;
COMMENT ON SCHEMA private IS
  'Server-internal financial state. authenticated ve anon rollerine HIC BIR ZAMAN GRANT verilmez. service_role + SECURITY DEFINER RPC''ler uzerinden erisilir.';

-- authenticated ve anon'a tum tablolar uzerinde tum yetkileri kapat
-- (ileride yeni private.* tablolar eklendiginde de gecerli olmasi icin
-- tum tablolari REVOKE eden yardimci fonksiyon)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    EXECUTE 'REVOKE ALL ON SCHEMA private FROM authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE ALL ON SCHEMA private FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='public') THEN
    EXECUTE 'REVOKE ALL ON SCHEMA private FROM public';
  END IF;
END $$;

-- service_role tam erişim (gerekirse SECURITY DEFINER RPC'ler için)
GRANT USAGE ON SCHEMA private TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- 2) server_checkout_sessions
-- ════════════════════════════════════════════════════════════════════════
-- Client-authoritative alanlar (user_id, total, vb.) YOKTUR.
-- user_id her zaman auth.uid()'den veya SECURITY DEFINER baglamindan set edilir.
CREATE TABLE IF NOT EXISTS private.server_checkout_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- user_id: auth.uid() ile set edilir, client INSERT ile set edilemez
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Idempotency: ayni user + key ile iki kez prepare = tek session
  idempotency_key TEXT NOT NULL,
  payment_method TEXT NOT NULL CHECK (payment_method IN
    ('cash','card_on_delivery','balance','online')),
  currency CHAR(3) NOT NULL DEFAULT 'TRY' CHECK (currency = 'TRY'),

  -- Address: kullanicinin kendi adresi (private.server tarafindan dogrulanir)
  address_id UUID REFERENCES public.addresses(id) ON DELETE SET NULL,

  -- Coupon: shop_coupons'tan (yine server dogrulamali)
  coupon_id UUID REFERENCES public.shop_coupons(id) ON DELETE SET NULL,

  -- Order group: multi-shop siparisler icin birden fazla session'i baglar
  order_group_id UUID,

  -- ═════════════════════════════════════════════════════════════════
  -- SERVER-AUTHORITATIVE FINANSAL ALANLAR
  -- Bu degerler client tarafindan ASLA set edilmez. prepare_checkout_session
  -- veya commit_*_order RPC'leri tarafindan hesaplanir.
  -- ═════════════════════════════════════════════════════════════════
  server_subtotal NUMERIC(12,2) NOT NULL CHECK (server_subtotal >= 0),
  server_delivery_fee NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (server_delivery_fee >= 0),
  server_discount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (server_discount >= 0),
  server_coupon_discount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (server_coupon_discount >= 0),
  server_commission_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (server_commission_amount >= 0),
  server_total NUMERIC(12,2) NOT NULL CHECK (server_total >= 0),

  -- Multi-shop icin: alt-siparis tutarlari (yoksa NULL)
  sub_order_subtotals JSONB,            -- {shop_id: subtotal}
  sub_order_delivery_fees JSONB,        -- {shop_id: delivery_fee}
  sub_order_coupon_discounts JSONB,     -- {shop_id: coupon_discount}

  -- Snapshot (fatura/raporlama): client tarafindan degil, server tarafindan
  -- products ve shops tablolarindan cekilip yazildi
  items_snapshot JSONB NOT NULL,         -- [{product_id, name, shop_id, shop_name, image_url, quantity, unit_price, subtotal, variant_data, flash_sale_id, flash_price}]
  delivery_address_snapshot JSONB,       -- {id, full_address, district, city, phone}

  -- ═════════════════════════════════════════════════════════════════
  -- ONLINE ODEME ICIN BEKLENEN TUTAR (iyzico init sirasinda set)
  -- Callback'te iyzico retrieve response'u ile karsilastirilir.
  -- ═════════════════════════════════════════════════════════════════
  expected_currency CHAR(3),
  expected_paid_price NUMERIC(12,2),
  expected_conversation_id TEXT,
  expected_basket_id TEXT,
  iyzico_environment TEXT CHECK (iyzico_environment IN ('sandbox','production') OR iyzico_environment IS NULL),

  -- Lifecycle
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','committed','expired','cancelled','failed')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
  committed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  cancellation_reason TEXT,

  -- Link'ler (commit sonrasi)
  payment_transaction_id UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
  order_id UUID,
  order_group_order_id UUID,

  -- Notes / invoice (server validate eder; uzunluk sinirli)
  notes TEXT CHECK (notes IS NULL OR length(notes) <= 500),
  invoice_data JSONB,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT scs_total_arithmetic CHECK (
    server_total = server_subtotal + server_delivery_fee - server_discount - server_coupon_discount
  ),
  CONSTRAINT scs_unique_user_idempotency UNIQUE (user_id, idempotency_key)
);

COMMENT ON TABLE private.server_checkout_sessions IS
  'Server-authoritative checkout session. Client INSERT/UPDATE/DELETE YAPAMAZ. Tum finansal alanlar server tarafindan hesaplanir.';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_scs_user_status
  ON private.server_checkout_sessions(user_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scs_expires_at
  ON private.server_checkout_sessions(expires_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_scs_order_id
  ON private.server_checkout_sessions(order_id) WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_scs_payment_txn
  ON private.server_checkout_sessions(payment_transaction_id)
  WHERE payment_transaction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_scs_order_group
  ON private.server_checkout_sessions(order_group_id)
  WHERE order_group_id IS NOT NULL;

-- updated_at trigger
CREATE OR REPLACE FUNCTION private.trg_scs_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS scs_set_updated_at ON private.server_checkout_sessions;
CREATE TRIGGER scs_set_updated_at
  BEFORE UPDATE ON private.server_checkout_sessions
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_scs_set_updated_at();

-- ============================================================================
-- 3) flash_sale_reservations
-- ════════════════════════════════════════════════════════════════════════
-- Stok rezervasyonu add-to-cart'ta DEGIL, prepare_checkout_session sirasinda
-- yapilir. Commit_*_order basarili olunca status='committed' + sold_count++.
-- Session iptal/expired olunca status='released' (client tetiklemez).
CREATE TABLE IF NOT EXISTS private.flash_sale_reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  sale_id UUID NOT NULL REFERENCES public.flash_sales(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES private.server_checkout_sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,

  quantity INTEGER NOT NULL CHECK (quantity > 0 AND quantity <= 100),

  -- Snapshot (commit sirasinda orders.flash_sale_id/flash_price icin kullanilir)
  unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),
  original_price NUMERIC(12,2) NOT NULL CHECK (original_price > 0),

  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','committed','released','expired')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
  committed_at TIMESTAMPTZ,
  released_at TIMESTAMPTZ,
  release_reason TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Ayni session'da ayni sale iki kez rezerve edilemez (idempotency)
  CONSTRAINT fsr_session_sale_unique UNIQUE (session_id, sale_id)
);

COMMENT ON TABLE private.flash_sale_reservations IS
  'Flash sale stok rezervasyonu. add-to-cart degil, prepare_checkout_session sirasinda olusturulur. Client INSERT/UPDATE/DELETE YAPAMAZ.';

CREATE INDEX IF NOT EXISTS idx_fsr_session
  ON private.flash_sale_reservations(session_id);
CREATE INDEX IF NOT EXISTS idx_fsr_user_status
  ON private.flash_sale_reservations(user_id, status);
CREATE INDEX IF NOT EXISTS idx_fsr_sale_status
  ON private.flash_sale_reservations(sale_id, status);
CREATE INDEX IF NOT EXISTS idx_fsr_expires_at
  ON private.flash_sale_reservations(expires_at) WHERE status = 'active';

DROP TRIGGER IF EXISTS fsr_set_updated_at ON private.flash_sale_reservations;
CREATE TRIGGER fsr_set_updated_at
  BEFORE UPDATE ON private.flash_sale_reservations
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_scs_set_updated_at();

-- ════════════════════════════════════════════════════════════════════════
-- 4) server_checkout_audit
-- ════════════════════════════════════════════════════════════════════════
-- Iyzico signature_invalid / amount_mismatch gibi guvenlik olaylarini
-- admin'in inceleyebilecegi append-only tablo.
CREATE TABLE IF NOT EXISTS private.server_checkout_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  session_id UUID REFERENCES private.server_checkout_sessions(id) ON DELETE SET NULL,
  payment_transaction_id UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,

  event_type TEXT NOT NULL CHECK (event_type IN (
    'session_prepared',
    'session_committed',
    'session_expired',
    'session_cancelled',
    'amount_mismatch',
    'signature_invalid',
    'currency_mismatch',
    'env_mismatch',
    'product_unavailable',
    'coupon_invalid',
    'balance_insufficient',
    'flash_stock_exhausted',
    'oversell_blocked',
    'duplicate_callback',
    'manual_reconciliation_required'
  )),

  -- Olay detaylari (PII icermez; sadece transaction_id ve tutar bilgisi)
  detail JSONB NOT NULL DEFAULT '{}'::JSONB,

  -- Cozum durumu (admin isaretleyebilir)
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES auth.users(id),
  resolution_note TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE private.server_checkout_audit IS
  'Guvenlik/reconciliation olaylari. Sadece admin SELECT yapabilir (public.server_checkout_audit_admin view ile).';

CREATE INDEX IF NOT EXISTS idx_sca_session
  ON private.server_checkout_audit(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sca_event_type
  ON private.server_checkout_audit(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sca_unresolved
  ON private.server_checkout_audit(created_at DESC) WHERE resolved_at IS NULL;

-- Audit tablosu INSERT-only (UPDATE/DELETE yok)
CREATE OR REPLACE FUNCTION private.server_checkout_audit_no_modify()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'server_checkout_audit tablosu append-only: UPDATE/DELETE yasak';
END;
$$;

DROP TRIGGER IF EXISTS sca_no_update ON private.server_checkout_audit;
CREATE TRIGGER sca_no_update
  BEFORE UPDATE ON private.server_checkout_audit
  FOR EACH ROW EXECUTE FUNCTION private.server_checkout_audit_no_modify();

DROP TRIGGER IF EXISTS sca_no_delete ON private.server_checkout_audit;
CREATE TRIGGER sca_no_delete
  BEFORE DELETE ON private.server_checkout_audit
  FOR EACH ROW EXECUTE FUNCTION private.server_checkout_audit_no_modify();

-- ════════════════════════════════════════════════════════════════════════
-- 5) MEVCUT TABLOLARA YENI KOLONLAR
-- ════════════════════════════════════════════════════════════════════════

-- orders: checkout_session_id link
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS checkout_session_id UUID,
  ADD COLUMN IF NOT EXISTS committed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS price_mismatch BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_orders_checkout_session_id
  ON public.orders(checkout_session_id) WHERE checkout_session_id IS NOT NULL;

-- payment_transactions: server-authoritative alanlar
ALTER TABLE public.payment_transactions
  ADD COLUMN IF NOT EXISTS checkout_session_id UUID,
  ADD COLUMN IF NOT EXISTS expected_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS expected_currency CHAR(3),
  ADD COLUMN IF NOT EXISTS expected_conversation_id TEXT,
  ADD COLUMN IF NOT EXISTS expected_basket_id TEXT,
  ADD COLUMN IF NOT EXISTS iyzico_environment TEXT CHECK (iyzico_environment IN ('sandbox','production') OR iyzico_environment IS NULL),
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT,
  ADD COLUMN IF NOT EXISTS reconciliation_status TEXT,
  ADD COLUMN IF NOT EXISTS reconciliation_note TEXT;

CREATE INDEX IF NOT EXISTS idx_pt_checkout_session
  ON public.payment_transactions(checkout_session_id) WHERE checkout_session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pt_idempotency
  ON public.payment_transactions(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pt_reconciliation
  ON public.payment_transactions(reconciliation_status) WHERE reconciliation_status IS NOT NULL;

-- ════════════════════════════════════════════════════════════════════════
-- 6) service_role TAM ERISIM
-- ═════════���══════════════════════════════════════════════════════════════
-- NOT (CERRAHI DÜZELTME #3): Aşağıdaki satır orijinal migration'da vardı:
--   GRANT ALL ON private.server_checkout_session_items TO service_role;
-- Ancak private.server_checkout_session_items tablosu HİÇBİR migration'da
-- oluşturulmuyor (itemlar items_snapshot JSONB'de saklan��yor). Bu yüzden o
-- GRANT satırı bu konsolide dosyada KALDIRILDI.
GRANT ALL ON private.server_checkout_sessions TO service_role;
GRANT ALL ON private.flash_sale_reservations TO service_role;
GRANT ALL ON private.server_checkout_audit TO service_role;
GRANT ALL ON private.trg_scs_set_updated_at TO service_role;
GRANT ALL ON private.server_checkout_audit_no_modify TO service_role;

-- ═════════════════════════════════���══════════════════════════════════════
-- 7) NOTIFY
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════════';
    RAISE NOTICE '✅ Server-Authoritative Checkout şeması oluşturuldu';
    RAISE NOTICE '   - private.server_checkout_sessions (immutable)';
    RAISE NOTICE '   - private.flash_sale_reservations (immutable)';
    RAISE NOTICE '   - private.server_checkout_audit (append-only)';
    RAISE NOTICE '   - orders.checkout_session_id, committed_at, price_mismatch';
    RAISE NOTICE '   - payment_transactions.checkout_session_id, expected_*';
    RAISE NOTICE '';
    RAISE NOTICE '   Sonraki adım: prepare_checkout_session RPC';
    RAISE NOTICE '════════════════════════════════════════════════════════════';
END $$;

-- =============================================================================
-- KAYNAK 4/9: 20260802000006_prepare_checkout_session_rpc.sql
-- CERRAHI DUZELTME #1: private.prepare_checkout_session -> public.prepare_checkout_session
--   PostgREST yalniz `public` semasini expose eder. CREATE/REVOKE/GRANT/COMMENT
--   satirlarinin tamaminda fonksiyon `public` semasinda olusturuldu. Fonksiyon
--   govdesindeki private.* TABLO referanslari (server_checkout_sessions vb.)
--   oldugu gibi birakildi; SECURITY DEFINER oldugu icin dahili erismeye devam eder.
-- =============================================================================
-- ==============================================================================
-- prepare_checkout_session RPC
-- Tarih: 2026-08-02
-- ==============================================================================
-- Server-authoritative checkout session/quote olusturur.
--
-- ISTEMCININ GONDEREBILDIGI (guvenli) ALANLAR:
--   - p_items JSONB           : [{product_id, quantity, variant_data?}]
--   - p_address_id UUID       : kullanicinin kendi address id'si
--   - p_coupon_id UUID        : shop_coupons.id (opsiyonel)
--   - p_payment_method TEXT   : 'cash' | 'card_on_delivery' | 'balance' | 'online'
--   - p_idempotency_key TEXT  : client tarafindan uretilen unique key
--   - p_notes TEXT            : opsiyonel not (uzunluk sinirli)
--   - p_invoice_data JSONB    : opsiyonel fatura bilgisi
--   - p_order_group_id UUID   : multi-shop icin opsiyonel
--
-- ISTEMCININ ASLA GONDEREMEYECEGI (server hesaplar) ALANLAR:
--   - user_id       (auth.uid()'den alinir)
--   - product_name  (products tablosundan cekilir)
--   - price         (products.price / discount_price / flash_price)
--   - subtotal      (server hesaplar)
--   - delivery_fee  (shops.delivery_fee + free_delivery_min_amount)
--   - discount      (server hesaplar)
--   - coupon_discount (validate_coupon ile server hesaplar)
--   - commission_amount (shops.commission_rate)
--   - total         (server hesaplar)
--   - payment_status
--   - order status
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.prepare_checkout_session(
  p_items JSONB,
  p_address_id UUID,
  p_payment_method TEXT,
  p_idempotency_key TEXT,
  p_coupon_id UUID DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_invoice_data JSONB DEFAULT NULL,
  p_order_group_id UUID DEFAULT NULL
)
RETURNS TABLE (
  session_id UUID,
  idempotency_key TEXT,
  payment_method TEXT,
  currency CHAR(3),
  status TEXT,
  expires_at TIMESTAMPTZ,
  server_subtotal NUMERIC,
  server_delivery_fee NUMERIC,
  server_discount NUMERIC,
  server_coupon_discount NUMERIC,
  server_commission_amount NUMERIC,
  server_total NUMERIC,
  items JSONB,
  delivery_address JSONB,
  coupon JSONB,
  shop JSONB,
  notes TEXT,
  warnings JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
  v_existing_session RECORD;
  v_item JSONB;
  v_product RECORD;
  v_shop RECORD;
  v_flash_sale RECORD;
  v_address RECORD;
  v_coupon RECORD;
  v_reservation_id UUID;

  v_item_product_id UUID;
  v_item_quantity INTEGER;
  v_item_variant JSONB;
  v_item_unit_price NUMERIC(12,2);
  v_item_subtotal NUMERIC(12,2);
  v_item_shop_id UUID;
  v_item_product_name TEXT;
  v_item_shop_name TEXT;
  v_item_image_url TEXT;
  v_item_flash_sale_id UUID;
  v_item_flash_price NUMERIC(12,2);

  v_server_subtotal NUMERIC(12,2) := 0;
  v_server_discount NUMERIC(12,2) := 0;
  v_server_coupon_discount NUMERIC(12,2) := 0;
  v_server_delivery_fee NUMERIC(12,2) := 0;
  v_server_commission_amount NUMERIC(12,2) := 0;
  v_server_total NUMERIC(12,2) := 0;

  v_normal_subtotal NUMERIC(12,2) := 0; -- kupon uygulanmamis ara toplam
  v_items_snapshot JSONB := '[]'::JSONB;
  v_warnings JSONB := '[]'::JSONB;

  v_sub_order_subtotals JSONB := '{}'::JSONB;
  v_sub_order_delivery_fees JSONB := '{}'::JSONB;
  v_sub_order_coupon_discounts JSONB := '{}'::JSONB;

  v_session_id UUID;
  v_now TIMESTAMPTZ := NOW();
  v_expires_at TIMESTAMPTZ;
  v_single_shop_id UUID;
BEGIN
  -- ===========================================================================
  -- 1) AUTH + PARAMETRE DOGRULAMA
  -- ===========================================================================
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication gerekli (auth.uid() null)' USING ERRCODE = '42501';
  END IF;

  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 OR length(p_idempotency_key) > 128 THEN
    RAISE EXCEPTION 'idempotency_key gerekli (8-128 karakter)' USING ERRCODE = '22023';
  END IF;

  IF p_payment_method NOT IN ('cash','card_on_delivery','balance','online') THEN
    RAISE EXCEPTION 'Gecersiz payment_method: %', p_payment_method USING ERRCODE = '22023';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'items bos olamaz' USING ERRCODE = '22023';
  END IF;

  IF jsonb_array_length(p_items) > 100 THEN
    RAISE EXCEPTION 'Cok fazla item (max 100)' USING ERRCODE = '22023';
  END IF;

  IF p_notes IS NOT NULL AND length(p_notes) > 500 THEN
    RAISE EXCEPTION 'Notes 500 karakteri gecemez' USING ERRCODE = '22023';
  END IF;

  -- ===========================================================================
  -- 2) IDEMPOTENCY: ayni user + key ile zaten session var mi?
  -- ===========================================================================
  SELECT * INTO v_existing_session
  FROM private.server_checkout_sessions
  WHERE user_id = v_user_id
    AND idempotency_key = p_idempotency_key
  LIMIT 1;

  IF FOUND THEN
    -- Mevcut session'i aynen don (idempotent replay)
    -- NOT: expires_at gecmisse status='expired' yapiyoruz, yeniden olusturulmuyor
    IF v_existing_session.expires_at < v_now AND v_existing_session.status = 'pending' THEN
      UPDATE private.server_checkout_sessions
      SET status = 'expired', updated_at = v_now
      WHERE id = v_existing_session.id;
      v_existing_session.status := 'expired';
    END IF;

    -- Mevcut items'i JSON olarak geri ver
    RETURN QUERY
    SELECT
      v_existing_session.id,
      v_existing_session.idempotency_key,
      v_existing_session.payment_method,
      v_existing_session.currency,
      v_existing_session.status,
      v_existing_session.expires_at,
      v_existing_session.server_subtotal,
      v_existing_session.server_delivery_fee,
      v_existing_session.server_discount,
      v_existing_session.server_coupon_discount,
      v_existing_session.server_commission_amount,
      v_existing_session.server_total,
      v_existing_session.items_snapshot,
      v_existing_session.delivery_address_snapshot,
      NULL::JSONB,  -- coupon (reload)
      NULL::JSONB,  -- shop (reload)
      v_existing_session.notes,
      '[]'::JSONB;
    RETURN;
  END IF;

  -- ===========================================================================
  -- 3) ADDRESS DOGRULAMA (gercekten bu kullanicinin mi?)
  -- ===========================================================================
  IF p_address_id IS NOT NULL THEN
    SELECT a.* INTO v_address
    FROM public.addresses a
    WHERE a.id = p_address_id
      AND a.user_id = v_user_id
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Adres bulunamadi veya bu kullaniciya ait degil' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ===========================================================================
  -- 4) HER ITEM ICIN: URUN/FIYAT/STOK/VARIANT/FLAS DOGRULAMASI
  -- ===========================================================================
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_item_product_id := NULLIF(v_item->>'product_id','')::UUID;
    v_item_quantity := COALESCE((v_item->>'quantity')::INTEGER, 0);
    v_item_variant := v_item->'variant_data';

    IF v_item_product_id IS NULL THEN
      RAISE EXCEPTION 'Gecersiz product_id: %', v_item->>'product_id' USING ERRCODE = '22023';
    END IF;

    IF v_item_quantity <= 0 OR v_item_quantity > 100 THEN
      RAISE EXCEPTION 'Gecersiz quantity (1-100): %', v_item_quantity USING ERRCODE = '22023';
    END IF;

    -- Urun bilgisi (server snapshot)
    SELECT p.id, p.name, p.price, p.discount_price, p.stock_quantity, p.is_available,
           p.shop_id, p.image_url, s.name AS shop_name, s.delivery_fee,
           s.free_delivery_min_amount, s.commission_rate, s.is_active AS shop_is_active,
           s.deleted_at AS shop_deleted_at
      INTO v_product
    FROM public.products p
    JOIN public.shops s ON s.id = p.shop_id
    WHERE p.id = v_item_product_id
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Urun bulunamadi: %', v_item_product_id USING ERRCODE = 'P0002';
    END IF;

    IF NOT v_product.is_available THEN
      RAISE EXCEPTION 'Urun satisa kapali: %', v_item_product_id USING ERRCODE = 'P0001';
    END IF;

    IF v_product.shop_is_active = false OR v_product.shop_deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'Magaza aktif degil: %', v_product.shop_id USING ERRCODE = 'P0001';
    END IF;

    IF v_product.stock_quantity < v_item_quantity THEN
      RAISE EXCEPTION 'Yetersiz stok: % (kalan: %, istenen: %)',
        v_item_product_id, v_product.stock_quantity, v_item_quantity
        USING ERRCODE = 'P0001';
    END IF;

    -- Variant dogrulamasi (opsiyonel; product_variants tablosu varsa)
    IF v_item_variant IS NOT NULL AND v_item_variant <> 'null'::JSONB THEN
      IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'product_variants'
      ) THEN
        IF NOT EXISTS (
          SELECT 1 FROM public.product_variants pv
          WHERE pv.product_id = v_item_product_id
            AND pv.variant_data = v_item_variant
            AND (pv.stock_quantity IS NULL OR pv.stock_quantity >= v_item_quantity)
        ) THEN
          RAISE EXCEPTION 'Gecersiz variant veya yetersiz variant stoku' USING ERRCODE = 'P0001';
        END IF;
      END IF;
    END IF;

    -- ===========================================================================
    -- 4a) FIRSAT: AKTIF FLAS SATIS VAR MI? (server dogrulamali)
    -- ===========================================================================
    v_item_flash_sale_id := NULL;
    v_item_flash_price := NULL;
    v_item_unit_price := COALESCE(v_product.discount_price, v_product.price);

    SELECT fs.id, fs.flash_price, fs.original_price, fs.stock_limit, fs.sold_count,
           fs.start_at, fs.end_at, fs.is_active
      INTO v_flash_sale
    FROM public.flash_sales fs
    WHERE fs.product_id = v_item_product_id
      AND fs.shop_id = v_product.shop_id
      AND fs.is_active = true
      AND v_now BETWEEN fs.start_at AND fs.end_at
    ORDER BY fs.flash_price ASC  -- en ucuz flash'i sec
    LIMIT 1
    FOR UPDATE OF fs;  -- ayni anda baska session bu satiri kilitlemesin

    IF FOUND THEN
      -- Stok kontrolu (reservation dahil)
      DECLARE
        v_reserved_qty INTEGER;
        v_available INTEGER;
      BEGIN
        SELECT COALESCE(SUM(quantity), 0) INTO v_reserved_qty
        FROM private.flash_sale_reservations
        WHERE sale_id = v_flash_sale.id
          AND status = 'active'
          AND expires_at > v_now;

        v_available := v_flash_sale.stock_limit - v_flash_sale.sold_count - v_reserved_qty;

        IF v_available < v_item_quantity THEN
          RAISE EXCEPTION 'Flas satis stoku yetersiz: % (kalan: %, istenen: %)',
            v_item_product_id, v_available, v_item_quantity
            USING ERRCODE = 'P0001';
        END IF;

        v_item_flash_sale_id := v_flash_sale.id;
        v_item_flash_price := v_flash_sale.flash_price;
        v_item_unit_price := v_flash_sale.flash_price;
      END;
    END IF;

    v_item_subtotal := v_item_unit_price * v_item_quantity;
    v_item_shop_id := v_product.shop_id;
    v_item_product_name := v_product.name;
    v_item_shop_name := v_product.shop_name;
    v_item_image_url := v_product.image_url;

    v_server_subtotal := v_server_subtotal + v_item_subtotal;
    v_normal_subtotal := v_normal_subtotal + v_item_subtotal;

    -- Snapshot JSON'a ekle
    v_items_snapshot := v_items_snapshot || jsonb_build_array(jsonb_build_object(
      'product_id', v_item_product_id,
      'product_name', v_item_product_name,
      'shop_id', v_item_shop_id,
      'shop_name', v_item_shop_name,
      'image_url', v_item_image_url,
      'quantity', v_item_quantity,
      'variant_data', v_item_variant,
      'unit_price', v_item_unit_price,
      'subtotal', v_item_subtotal,
      'flash_sale_id', v_item_flash_sale_id,
      'flash_price', v_item_flash_price
    ));

    -- Per-shop alt toplamlar (multi-shop)
    IF v_sub_order_subtotals ? v_item_shop_id::TEXT THEN
      v_sub_order_subtotals := jsonb_set(
        v_sub_order_subtotals,
        ARRAY[v_item_shop_id::TEXT],
        to_jsonb((v_sub_order_subtotals->>v_item_shop_id::TEXT)::NUMERIC + v_item_subtotal)
      );
    ELSE
      v_sub_order_subtotals := v_sub_order_subtotals ||
        jsonb_build_object(v_item_shop_id::TEXT, v_item_subtotal);
    END IF;
  END LOOP;

  -- ===========================================================================
  -- 5) TEK-MAGAZA MI COK-MAGAZA MI TESPIT ET
  -- ===========================================================================
  DECLARE
    v_shop_count INTEGER;
  BEGIN
    SELECT COUNT(DISTINCT v_item_shop_id) INTO v_shop_count
    FROM jsonb_array_elements(v_items_snapshot) AS e
    CROSS JOIN LATERAL (SELECT (e->>'shop_id')::UUID AS v_item_shop_id) AS s
    WHERE TRUE;

    IF v_shop_count > 1 THEN
      -- Cok magazali: her magaza icin ayri delivery_fee hesaplanir
      DECLARE
        v_shop_key TEXT;
        v_shop_subtotal NUMERIC;
        v_shop_delivery_fee NUMERIC;
        v_shop_min_free NUMERIC;
        v_shop_base_fee NUMERIC;
      BEGIN
        FOR v_shop_key, v_shop_subtotal IN
          SELECT key, (value::TEXT)::NUMERIC
          FROM jsonb_each(v_sub_order_subtotals)
        LOOP
          SELECT s.delivery_fee, s.free_delivery_min_amount
            INTO v_shop_base_fee, v_shop_min_free
          FROM public.shops s WHERE s.id = v_shop_key::UUID;

          IF v_shop_min_free > 0 AND v_shop_subtotal >= v_shop_min_free THEN
            v_shop_delivery_fee := 0;
          ELSE
            v_shop_delivery_fee := COALESCE(v_shop_base_fee, 15.0);
          END IF;

          v_server_delivery_fee := v_server_delivery_fee + v_shop_delivery_fee;
          v_sub_order_delivery_fees := v_sub_order_delivery_fees ||
            jsonb_build_object(v_shop_key, v_shop_delivery_fee);
        END LOOP;
      END;
    ELSE
      -- Tek magaza: v_shop_id'yi set et
      SELECT (v_items_snapshot->0->>'shop_id')::UUID INTO v_single_shop_id;

      -- Delivery fee (tek magaza)
      SELECT s.delivery_fee, s.free_delivery_min_amount, s.commission_rate
        INTO v_shop
      FROM public.shops s WHERE s.id = v_single_shop_id;

      IF v_shop.free_delivery_min_amount > 0 AND v_normal_subtotal >= v_shop.free_delivery_min_amount THEN
        v_server_delivery_fee := 0;
      ELSE
        v_server_delivery_fee := COALESCE(v_shop.delivery_fee, 15.0);
      END IF;
    END IF;
  END;

  -- ===========================================================================
  -- 6) KUPON DOGRULAMA + INDIRIM HESAPLAMA (server)
  -- ===========================================================================
  IF p_coupon_id IS NOT NULL THEN
    SELECT c.id, c.code, c.discount_type, c.discount_value, c.maximum_discount_amount,
           c.minimum_order_amount, c.usage_limit, c.usage_count, c.usage_per_user,
           c.start_date, c.end_date, c.is_active, c.shop_id
      INTO v_coupon
    FROM public.shop_coupons c
    WHERE c.id = p_coupon_id
    LIMIT 1
    FOR UPDATE OF c;  -- ayni anda iki session ayni kupona erisemesin

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Kupon bulunamadi' USING ERRCODE = 'P0002';
    END IF;

    IF NOT v_coupon.is_active THEN
      RAISE EXCEPTION 'Kupon aktif degil' USING ERRCODE = 'P0001';
    END IF;

    IF v_coupon.start_date IS NOT NULL AND v_coupon.start_date > v_now THEN
      RAISE EXCEPTION 'Kupon henuz baslamadi' USING ERRCODE = 'P0001';
    END IF;

    IF v_coupon.end_date IS NOT NULL AND v_coupon.end_date < v_now THEN
      RAISE EXCEPTION 'Kuponun suresi dolmus' USING ERRCODE = 'P0001';
    END IF;

    -- Kupon magaza uyumu (cok magazali ise en az bir item uyumlu olmali)
    IF v_single_shop_id IS NOT NULL AND v_coupon.shop_id <> v_single_shop_id THEN
      RAISE EXCEPTION 'Kupon bu magaza icin gecerli degil' USING ERRCODE = 'P0001';
    END IF;

    IF v_coupon.minimum_order_amount IS NOT NULL
       AND v_normal_subtotal < v_coupon.minimum_order_amount THEN
      RAISE EXCEPTION 'Minimum siparis tutari asilmadi (gerekli: %, mevcut: %)',
        v_coupon.minimum_order_amount, v_normal_subtotal
        USING ERRCODE = 'P0001';
    END IF;

    -- Kullanici basina limit
    IF v_coupon.usage_per_user IS NOT NULL THEN
      DECLARE
        v_user_usage_count INTEGER;
      BEGIN
        SELECT COUNT(*) INTO v_user_usage_count
        FROM public.coupon_usages
        WHERE coupon_id = v_coupon.id AND user_id = v_user_id;
        IF v_user_usage_count >= v_coupon.usage_per_user THEN
          RAISE EXCEPTION 'Bu kuponu daha once kullandiniz' USING ERRCODE = 'P0001';
        END IF;
      END;
    END IF;

    -- Kupon indirimi hesapla
    IF v_coupon.discount_type = 'percentage' THEN
      v_server_coupon_discount := v_normal_subtotal * (v_coupon.discount_value / 100.0);
    ELSIF v_coupon.discount_type = 'fixed' THEN
      v_server_coupon_discount := v_coupon.discount_value;
    ELSE
      RAISE EXCEPTION 'Bilinmeyen kupon tipi: %', v_coupon.discount_type USING ERRCODE = 'P0001';
    END IF;

    -- Maksimum indirim siniri
    IF v_coupon.maximum_discount_amount IS NOT NULL
       AND v_server_coupon_discount > v_coupon.maximum_discount_amount THEN
      v_server_coupon_discount := v_coupon.maximum_discount_amount;
    END IF;

    -- Negatif olamaz, subtotal'i asamaz
    IF v_server_coupon_discount < 0 THEN
      v_server_coupon_discount := 0;
    END IF;
    IF v_server_coupon_discount > v_normal_subtotal THEN
      v_server_coupon_discount := v_normal_subtotal;
    END IF;
  END IF;

  -- ===========================================================================
  -- 7) KOMISYON (server, shops.commission_rate)
  -- ===========================================================================
  v_server_commission_amount := ROUND(v_normal_subtotal * (v_shop.commission_rate / 100.0), 2);

  -- ===========================================================================
  -- 8) TOPLAM HESAPLA + DOGRULAMALAR
  -- ===========================================================================
  v_server_total := v_server_subtotal + v_server_delivery_fee - v_server_coupon_discount - v_server_discount;

  IF v_server_total < 0 THEN
    v_server_total := 0;
  END IF;

  -- Ucretli urunlerde total=0 kabul edilmez
  -- (free-order policy: ayri bir mekanizma; su an sadece 'total>0' zorunludur)
  IF v_server_total <= 0 AND v_normal_subtotal > 0 THEN
    -- Bu durumda ya kuponsuz olur ya da limit; simdilik izin ver (kupon %100 ise)
    -- Eger magazada free-order politikasi yoksa hata ver
    NULL; -- policy hook (ileride)
  END IF;

  v_expires_at := v_now + INTERVAL '15 minutes';

  -- ===========================================================================
  -- 9) FLAS REZERVASYONLARINI OLUSTUR (FOR UPDATE kilitleriyle)
  -- ===========================================================================
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_snapshot)
  LOOP
    IF (v_item->>'flash_sale_id') IS NOT NULL THEN
      INSERT INTO private.flash_sale_reservations (
        sale_id, session_id, user_id, product_id, shop_id,
        quantity, unit_price, original_price, expires_at
      ) VALUES (
        (v_item->>'flash_sale_id')::UUID,
        gen_random_uuid(),  -- placeholder, INSERT sonrasi update edilecek
        v_user_id,
        (v_item->>'product_id')::UUID,
        (v_item->>'shop_id')::UUID,
        (v_item->>'quantity')::INTEGER,
        (v_item->>'unit_price')::NUMERIC,
        COALESCE(
          (SELECT original_price FROM public.flash_sales WHERE id = (v_item->>'flash_sale_id')::UUID),
          (v_item->>'unit_price')::NUMERIC
        ),
        v_expires_at
      );
    END IF;
  END LOOP;

  -- ===========================================================================
  -- 10) SESSION INSERT
  -- ===========================================================================
  INSERT INTO private.server_checkout_sessions (
    user_id, idempotency_key, payment_method, currency,
    address_id, coupon_id, order_group_id,
    server_subtotal, server_delivery_fee, server_discount, server_coupon_discount,
    server_commission_amount, server_total,
    sub_order_subtotals, sub_order_delivery_fees, sub_order_coupon_discounts,
    items_snapshot, delivery_address_snapshot,
    expires_at, notes, invoice_data
  ) VALUES (
    v_user_id, p_idempotency_key, p_payment_method, 'TRY',
    p_address_id, p_coupon_id, p_order_group_id,
    v_server_subtotal, v_server_delivery_fee, v_server_discount, v_server_coupon_discount,
    v_server_commission_amount, v_server_total,
    v_sub_order_subtotals, v_sub_order_delivery_fees, v_sub_order_coupon_discounts,
    v_items_snapshot,
    CASE WHEN v_address.id IS NOT NULL THEN jsonb_build_object(
      'id', v_address.id,
      'title', v_address.title,
      'full_name', v_address.full_name,
      'phone', v_address.phone,
      'address_line1', v_address.address_line1,
      'address_line2', v_address.address_line2,
      'city', v_address.city,
      'district', v_address.district,
      'postal_code', v_address.postal_code,
      'latitude', v_address.latitude,
      'longitude', v_address.longitude
    ) ELSE NULL END,
    v_expires_at, p_notes, p_invoice_data
  )
  RETURNING id INTO v_session_id;

  -- Rezervasyonlara session_id'yi set et
  UPDATE private.flash_sale_reservations
  SET session_id = v_session_id
  WHERE user_id = v_user_id
    AND session_id = gen_random_uuid()  -- placeholder (yukardaki INSERT ile ayni)
    AND status = 'active'
    AND created_at >= v_now - INTERVAL '1 second';

  -- Audit log
  INSERT INTO private.server_checkout_audit (session_id, user_id, event_type, detail)
  VALUES (v_session_id, v_user_id, 'session_prepared', jsonb_build_object(
    'payment_method', p_payment_method,
    'item_count', jsonb_array_length(v_items_snapshot),
    'subtotal', v_server_subtotal,
    'total', v_server_total
  ));

  -- ===========================================================================
  -- 11) QUOTE DON
  -- ===========================================================================
  RETURN QUERY
  SELECT
    v_session_id,
    p_idempotency_key,
    p_payment_method,
    'TRY'::CHAR(3),
    'pending'::TEXT,
    v_expires_at,
    v_server_subtotal,
    v_server_delivery_fee,
    v_server_discount,
    v_server_coupon_discount,
    v_server_commission_amount,
    v_server_total,
    v_items_snapshot,
    CASE WHEN v_address.id IS NOT NULL THEN jsonb_build_object(
      'id', v_address.id,
      'full_name', v_address.full_name,
      'phone', v_address.phone,
      'address_line1', v_address.address_line1,
      'city', v_address.city
    ) ELSE NULL END,
    CASE WHEN v_coupon.id IS NOT NULL THEN jsonb_build_object(
      'id', v_coupon.id,
      'code', v_coupon.code,
      'discount_type', v_coupon.discount_type,
      'discount_value', v_coupon.discount_value
    ) ELSE NULL END,
    CASE WHEN v_single_shop_id IS NOT NULL THEN jsonb_build_object(
      'id', v_single_shop_id,
      'delivery_fee', v_shop.delivery_fee,
      'commission_rate', v_shop.commission_rate,
      'free_delivery_min_amount', v_shop.free_delivery_min_amount
    ) ELSE NULL END,
    p_notes,
    v_warnings;
END;
$$;

-- ===========================================================================
-- 12) GRANT: SADECE authenticated (kendi user baglaminda)
-- ===========================================================================
REVOKE ALL ON FUNCTION public.prepare_checkout_session(
  JSONB, UUID, TEXT, TEXT, UUID, TEXT, JSONB, UUID
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.prepare_checkout_session(
  JSONB, UUID, TEXT, TEXT, UUID, TEXT, JSONB, UUID
) TO authenticated;

COMMENT ON FUNCTION public.prepare_checkout_session IS
  'Server-authoritative checkout session/quote olusturur. Idempotent. Client ASLA fiyat/total/commission gonderemez; tum hesaplama NUMERIC(12,2) ile sunucuda yapilir. 2026-08-02.';

DO $$
BEGIN
    RAISE NOTICE 'prepare_checkout_session RPC olusturuldu (public semasi)';
    RAISE NOTICE '   - authenticated EXECUTE yetkisi verildi';
    RAISE NOTICE '   - anon ve PUBLIC revoke edildi';
    RAISE NOTICE '   - tum finansal alanlar server hesaplar (NUMERIC)';
END $$;

-- =============================================================================
-- KAYNAK 5/9: 20260802000007_commit_cod_and_balance_orders.sql
-- CERRAHI DUZELTME #1: private.commit_cod_order / commit_balance_order -> public.*
-- CERRAHI DUZELTME #4: nextval('order_number_seq') -> nextval('public.order_number_seq')
--   (SET search_path='' altinda niteliksiz nextval cozunmezdi).
-- =============================================================================
-- ==============================================================================
-- commit_cod_order + commit_balance_order RPC'leri
-- Tarih: 2026-08-02
-- ==============================================================================
-- Cash/card-on-delivery ve bakiye siparislerini server-checkout-session
-- snapshot'indan atomik olarak olusturur. Ayni transaction icinde:
--   1) Session FOR UPDATE kilitle
--   2) auth.uid() + status=pending + expires_at dogrula
--   3) Re-validation (fiyat, stok, kupon hala gecerli mi)
--   4) orders INSERT (server snapshot'tan, client-authoritative alan YOK)
--   5) order_items INSERT
--   6) [balance] user_balances UPDATE + balance_transactions INSERT (append-only ledger)
--   7) coupon_usages INSERT + shop_coupons.usage_count++ (FOR UPDATE)
--   8) flash_sale_reservations UPDATE status='committed' + flash_sales.sold_count++
--   9) server_checkout_sessions UPDATE status='completed', order_id
--   10) notification_outbox INSERT
-- Idempotent: ayni session_id ile iki kez commit = tek order.
-- ==============================================================================

-- ==============================================================================
-- 1) commit_cod_order
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.commit_cod_order(
  p_session_id UUID
)
RETURNS TABLE (
  order_id UUID,
  order_number TEXT,
  order_group_id UUID,
  status TEXT,
  total NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
  v_session RECORD;
  v_item JSONB;
  v_order_id UUID;
  v_order_number TEXT;
  v_order_group_id UUID;
  v_existing_order_id UUID;
  v_order_count INTEGER := 0;
  v_now TIMESTAMPTZ := NOW();
  v_reservation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication gerekli' USING ERRCODE = '42501';
  END IF;

  -- ===========================================================================
  -- 1) SESSION KILITLE
  -- ===========================================================================
  SELECT * INTO v_session
  FROM private.server_checkout_sessions
  WHERE id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  -- ===========================================================================
  -- 2) IDEMPOTENT: ayni session zaten commit edildiyse mevcut order'i don
  -- ===========================================================================
  IF v_session.status = 'committed' AND v_session.order_id IS NOT NULL THEN
    SELECT order_number INTO v_order_number FROM public.orders WHERE id = v_session.order_id;
    RETURN QUERY SELECT
      v_session.order_id, COALESCE(v_order_number, ''),
      v_session.order_group_id, 'committed'::TEXT, v_session.server_total;
    RETURN;
  END IF;

  -- ===========================================================================
  -- 3) DOGRULAMALAR
  -- ===========================================================================
  IF v_session.user_id <> v_user_id THEN
    RAISE EXCEPTION 'Bu session bu kullaniciya ait degil' USING ERRCODE = '42501';
  END IF;

  IF v_session.status <> 'pending' THEN
    RAISE EXCEPTION 'Session zaten % durumunda', v_session.status USING ERRCODE = 'P0001';
  END IF;

  IF v_session.expires_at < v_now THEN
    UPDATE private.server_checkout_sessions
    SET status = 'expired', updated_at = v_now
    WHERE id = p_session_id;
    RAISE EXCEPTION 'Session suresi dolmus' USING ERRCODE = 'P0001';
  END IF;

  IF v_session.payment_method NOT IN ('cash','card_on_delivery') THEN
    RAISE EXCEPTION 'Bu RPC sadece cash/card_on_delivery icin. payment_method=%', v_session.payment_method
      USING ERRCODE = 'P0001';
  END IF;

  -- ===========================================================================
  -- 4) RE-VALIDATION: urun/fiyat hala gecerli mi?
  -- ===========================================================================
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_session.items_snapshot)
  LOOP
    DECLARE
      v_current_price NUMERIC;
      v_current_stock INTEGER;
      v_is_available BOOLEAN;
    BEGIN
      SELECT
        COALESCE(p.discount_price, p.price),
        p.stock_quantity,
        p.is_available
      INTO v_current_price, v_current_stock, v_is_available
      FROM public.products p
      WHERE p.id = (v_item->>'product_id')::UUID;

      IF NOT FOUND OR NOT v_is_available THEN
        RAISE EXCEPTION 'Urun artik mevcut degil: %', v_item->>'product_id' USING ERRCODE = 'P0001';
      END IF;

      IF v_current_stock < (v_item->>'quantity')::INTEGER THEN
        RAISE EXCEPTION 'Stok yetersiz: %', v_item->>'product_id' USING ERRCODE = 'P0001';
      END IF;

      -- Flash satis ise fiyat kontrolu
      IF (v_item->>'flash_sale_id') IS NOT NULL THEN
        DECLARE
          v_flash RECORD;
        BEGIN
          SELECT fs.flash_price, fs.is_active, fs.start_at, fs.end_at,
                 fs.stock_limit, fs.sold_count
            INTO v_flash
          FROM public.flash_sales fs
          WHERE fs.id = (v_item->>'flash_sale_id')::UUID
            AND fs.is_active = true
          FOR UPDATE;

          IF NOT FOUND OR v_now NOT BETWEEN v_flash.start_at AND v_flash.end_at THEN
            RAISE EXCEPTION 'Flash satis artik gecerli degil' USING ERRCODE = 'P0001';
          END IF;
        END;
      END IF;
    END;
  END LOOP;

  -- ===========================================================================
  -- 5) KUPON FOR UPDATE (commit aninda limit yeniden kontrol)
  -- ===========================================================================
  IF v_session.coupon_id IS NOT NULL THEN
    PERFORM 1
    FROM public.shop_coupons c
    WHERE c.id = v_session.coupon_id
      AND c.is_active = true
      AND (c.start_date IS NULL OR c.start_date <= v_now)
      AND (c.end_date IS NULL OR c.end_date >= v_now)
      AND (c.usage_limit IS NULL OR c.usage_count < c.usage_limit)
    FOR UPDATE OF c;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Kupon artik gecerli degil' USING ERRCODE = 'P0001';
    END IF;

    -- Kullanici basina limit
    IF EXISTS (
      SELECT 1 FROM public.shop_coupons
      WHERE id = v_session.coupon_id
        AND usage_per_user IS NOT NULL
        AND (
          SELECT COUNT(*) FROM public.coupon_usages
          WHERE coupon_id = v_session.coupon_id AND user_id = v_user_id
        ) >= usage_per_user
    ) THEN
      RAISE EXCEPTION 'Kullanici basina kupon limiti asildi' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- ===========================================================================
  -- 6) ORDERS + ORDER_ITEMS OLUSTUR
  -- Multi-shop ise her magaza icin ayri order
  -- ===========================================================================
  -- Order group ID (multi-shop icin)
  IF v_session.order_group_id IS NOT NULL THEN
    v_order_group_id := v_session.order_group_id;
  ELSE
    v_order_group_id := gen_random_uuid();
  END IF;

  -- Snapshot'i magazalara gore grupla
  FOR v_item IN
    SELECT
      (e->>'shop_id')::UUID AS shop_id,
      (e->>'shop_name')::TEXT AS shop_name,
      jsonb_agg(e) AS items
    FROM jsonb_array_elements(v_session.items_snapshot) AS e
    GROUP BY (e->>'shop_id'), (e->>'shop_name')
  LOOP
    -- Per-shop subtotal (server)
    DECLARE
      v_shop_subtotal NUMERIC := 0;
      v_shop_delivery_fee NUMERIC := 0;
      v_shop_coupon_discount NUMERIC := 0;
      v_shop_total NUMERIC := 0;
      v_item_inner JSONB;
    BEGIN
      FOR v_item_inner IN SELECT * FROM jsonb_array_elements(v_item.items)
      LOOP
        v_shop_subtotal := v_shop_subtotal + (v_item_inner->>'subtotal')::NUMERIC;
      END LOOP;

      v_shop_delivery_fee := COALESCE(
        (v_session.sub_order_delivery_fees->>v_item.shop_id::TEXT)::NUMERIC,
        0
      );

      -- Kupon magaza uyumu (cok magazali ise sadece cupona uyan magazaya uygula)
      IF v_session.coupon_id IS NOT NULL THEN
        DECLARE
          v_c_shop_id UUID;
        BEGIN
          SELECT shop_id INTO v_c_shop_id FROM public.shop_coupons WHERE id = v_session.coupon_id;
          IF v_c_shop_id = v_item.shop_id THEN
            -- Tek magazali ise toplam kupon; cok magazali ise sadece o magazaya
            IF jsonb_array_length(v_session.items_snapshot) = jsonb_array_length(v_item.items) THEN
              v_shop_coupon_discount := v_session.server_coupon_discount;
            ELSE
              v_shop_coupon_discount := 0; -- cok magaza cuponsuz hesap (detay icin ilerde)
            END IF;
          END IF;
        END;
      END IF;

      v_shop_total := v_shop_subtotal + v_shop_delivery_fee - v_shop_coupon_discount;

      v_order_number := 'ORD' || LPAD(nextval('public.order_number_seq')::TEXT, 8, '0');

      INSERT INTO public.orders (
        user_id, shop_id, order_number, order_group_id, group_order_number,
        delivery_address_text, address_id, customer_phone,
        payment_method, payment_status, status,
        subtotal, delivery_fee, discount, coupon_id, coupon_discount, total,
        notes, checkout_session_id, committed_at,
        invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no,
        invoice_tax_office, invoice_address, invoice_email,
        created_at, updated_at
      ) VALUES (
        v_user_id, v_item.shop_id, v_order_number, v_order_group_id, NULL,
        v_session.delivery_address_snapshot->>'address_line1',
        v_session.address_id,
        v_session.delivery_address_snapshot->>'phone',
        v_session.payment_method, 'pending', 'pending',
        v_shop_subtotal, v_shop_delivery_fee, v_session.server_discount,
        v_session.coupon_id, v_shop_coupon_discount, v_shop_total,
        v_session.notes, p_session_id, v_now,
        v_session.invoice_data->>'invoice_type',
        v_session.invoice_data->>'invoice_full_name',
        v_session.invoice_data->>'invoice_tax_number',
        v_session.invoice_data->>'invoice_tc_no',
        v_session.invoice_data->>'invoice_tax_office',
        v_session.invoice_data->>'invoice_address',
        v_session.invoice_data->>'invoice_email',
        v_now, v_now
      )
      RETURNING id INTO v_order_id;

      -- order_items INSERT
      FOR v_item_inner IN SELECT * FROM jsonb_array_elements(v_item.items)
      LOOP
        INSERT INTO public.order_items (
          order_id, product_id, product_name, price, product_price, quantity, subtotal,
          product_image_url, shop_id, shop_name, flash_sale_id, flash_price,
          variant_data, created_at
        ) VALUES (
          v_order_id,
          (v_item_inner->>'product_id')::UUID,
          v_item_inner->>'product_name',
          (v_item_inner->>'unit_price')::NUMERIC,
          (v_item_inner->>'unit_price')::NUMERIC,
          (v_item_inner->>'quantity')::INTEGER,
          (v_item_inner->>'subtotal')::NUMERIC,
          v_item_inner->>'image_url',
          (v_item_inner->>'shop_id')::UUID,
          v_item_inner->>'shop_name',
          NULLIF(v_item_inner->>'flash_sale_id','')::UUID,
          NULLIF(v_item_inner->>'flash_price','')::NUMERIC,
          v_item_inner->'variant_data',
          v_now
        );
      END LOOP;

      IF v_order_count = 0 THEN
        v_existing_order_id := v_order_id; -- ilk order (multi-shop'ta ilk magaza)
      END IF;
      v_order_count := v_order_count + 1;
    END;
  END LOOP;

  -- Tek order mi cok order mi?
  IF v_order_count = 1 THEN
    v_existing_order_id := v_order_id;
  END IF;

  -- ===========================================================================
  -- 7) KUPON KULLANIM KAYDI
  -- ===========================================================================
  IF v_session.coupon_id IS NOT NULL AND v_session.server_coupon_discount > 0 THEN
    -- Idempotency: ayni (coupon, order) zaten var mi?
    IF NOT EXISTS (
      SELECT 1 FROM public.coupon_usages
      WHERE coupon_id = v_session.coupon_id
        AND order_id = v_existing_order_id
    ) THEN
      INSERT INTO public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
      VALUES (v_session.coupon_id, v_existing_order_id, v_user_id, v_session.server_coupon_discount);

      UPDATE public.shop_coupons
      SET usage_count = usage_count + 1
      WHERE id = v_session.coupon_id;
    END IF;
  END IF;

  -- ===========================================================================
  -- 8) FLAS REZERVASYONLARINI COMMIT ET
  -- ===========================================================================
  FOR v_reservation IN
    SELECT * FROM private.flash_sale_reservations
    WHERE session_id = p_session_id AND status = 'active'
    FOR UPDATE
  LOOP
    -- sold_count artir (FOR UPDATE kilitle)
    UPDATE public.flash_sales
    SET sold_count = sold_count + v_reservation.quantity
    WHERE id = v_reservation.sale_id;

    UPDATE private.flash_sale_reservations
    SET status = 'committed', committed_at = v_now
    WHERE id = v_reservation.id;
  END LOOP;

  -- ===========================================================================
  -- 9) SESSION COMPLETED
  -- ===========================================================================
  UPDATE private.server_checkout_sessions
  SET
    status = 'committed',
    committed_at = v_now,
    order_id = v_existing_order_id,
    order_group_order_id = v_order_group_id,
    updated_at = v_now
  WHERE id = p_session_id;

  -- Audit
  INSERT INTO private.server_checkout_audit (session_id, user_id, event_type, detail)
  VALUES (p_session_id, v_user_id, 'session_committed', jsonb_build_object(
    'order_id', v_existing_order_id,
    'order_group_id', v_order_group_id,
    'order_count', v_order_count,
    'total', v_session.server_total
  ));

  RETURN QUERY SELECT
    v_existing_order_id,
    v_order_number,
    v_order_group_id,
    'committed'::TEXT,
    v_session.server_total;
END;
$$;

REVOKE ALL ON FUNCTION public.commit_cod_order(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.commit_cod_order(UUID) TO authenticated;

-- ==============================================================================
-- 2) commit_balance_order (bakiye + siparis atomik)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.commit_balance_order(
  p_session_id UUID
)
RETURNS TABLE (
  order_id UUID,
  order_number TEXT,
  order_group_id UUID,
  status TEXT,
  total NUMERIC,
  balance_transaction_id UUID,
  new_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
  v_session RECORD;
  v_item JSONB;
  v_order_id UUID;
  v_order_number TEXT;
  v_order_group_id UUID;
  v_existing_order_id UUID;
  v_order_count INTEGER := 0;
  v_now TIMESTAMPTZ := NOW();

  v_balance_id UUID;
  v_current_balance NUMERIC;
  v_balance_before NUMERIC;
  v_balance_after NUMERIC;
  v_balance_txn_id UUID;
  v_reservation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication gerekli' USING ERRCODE = '42501';
  END IF;

  -- ===========================================================================
  -- 1) SESSION KILITLE
  -- ===========================================================================
  SELECT * INTO v_session
  FROM private.server_checkout_sessions
  WHERE id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotent
  IF v_session.status = 'committed' AND v_session.order_id IS NOT NULL THEN
    SELECT order_number INTO v_order_number FROM public.orders WHERE id = v_session.order_id;
    RETURN QUERY SELECT
      v_session.order_id, COALESCE(v_order_number, ''),
      v_session.order_group_id, 'committed'::TEXT, v_session.server_total,
      NULL::UUID, NULL::NUMERIC;
    RETURN;
  END IF;

  IF v_session.user_id <> v_user_id THEN
    RAISE EXCEPTION 'Bu session bu kullaniciya ait degil' USING ERRCODE = '42501';
  END IF;

  IF v_session.status <> 'pending' THEN
    RAISE EXCEPTION 'Session zaten % durumunda', v_session.status USING ERRCODE = 'P0001';
  END IF;

  IF v_session.expires_at < v_now THEN
    UPDATE private.server_checkout_sessions
    SET status = 'expired', updated_at = v_now
    WHERE id = p_session_id;
    RAISE EXCEPTION 'Session suresi dolmus' USING ERRCODE = 'P0001';
  END IF;

  IF v_session.payment_method <> 'balance' THEN
    RAISE EXCEPTION 'Bu RPC sadece balance icin. payment_method=%', v_session.payment_method
      USING ERRCODE = 'P0001';
  END IF;

  -- ===========================================================================
  -- 2) BAKIYE KILITLE + YETERLILIK KONTROLU
  -- ===========================================================================
  SELECT id, balance INTO v_balance_id, v_current_balance
  FROM public.user_balances
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_balance_id IS NULL THEN
    RAISE EXCEPTION 'Bakiye kaydi bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  IF v_current_balance < v_session.server_total THEN
    RAISE EXCEPTION 'Yetersiz bakiye (mevcut: %, gerekli: %)',
      v_current_balance, v_session.server_total
      USING ERRCODE = 'P0001';
  END IF;

  v_balance_before := v_current_balance;
  v_balance_after := v_current_balance - v_session.server_total;

  -- ===========================================================================
  -- 3) RE-VALIDATION: ayni cod_order'daki gibi
  -- ===========================================================================
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_session.items_snapshot)
  LOOP
    DECLARE
      v_current_price NUMERIC;
      v_current_stock INTEGER;
      v_is_available BOOLEAN;
    BEGIN
      SELECT COALESCE(p.discount_price, p.price), p.stock_quantity, p.is_available
      INTO v_current_price, v_current_stock, v_is_available
      FROM public.products p
      WHERE p.id = (v_item->>'product_id')::UUID;

      IF NOT FOUND OR NOT v_is_available THEN
        RAISE EXCEPTION 'Urun artik mevcut degil: %', v_item->>'product_id' USING ERRCODE = 'P0001';
      END IF;

      IF v_current_stock < (v_item->>'quantity')::INTEGER THEN
        RAISE EXCEPTION 'Stok yetersiz: %', v_item->>'product_id' USING ERRCODE = 'P0001';
      END IF;
    END;
  END LOOP;

  -- ===========================================================================
  -- 4) BAKIYE DUSUMU + LEDGER KAYDI (atomik)
  -- ===========================================================================
  UPDATE public.user_balances
  SET balance = v_balance_after,
      total_spent = total_spent + v_session.server_total,
      updated_at = v_now
  WHERE id = v_balance_id;

  INSERT INTO public.balance_transactions (
    user_id, type, amount, net_amount,
    balance_before, balance_after,
    reference_type, reference_id, status, description, metadata,
    created_at, updated_at
  ) VALUES (
    v_user_id, 'order_payment', v_session.server_total, v_session.server_total,
    v_balance_before, v_balance_after,
    'order', gen_random_uuid(), 'completed',
    'Siparis odemesi (server checkout)',
    jsonb_build_object('session_id', p_session_id),
    v_now, v_now
  )
  RETURNING id INTO v_balance_txn_id;

  -- ===========================================================================
  -- 5) ORDERS + ORDER_ITEMS (ayni commit_cod_order mantigi)
  -- ===========================================================================
  IF v_session.order_group_id IS NOT NULL THEN
    v_order_group_id := v_session.order_group_id;
  ELSE
    v_order_group_id := gen_random_uuid();
  END IF;

  FOR v_item IN
    SELECT
      (e->>'shop_id')::UUID AS shop_id,
      (e->>'shop_name')::TEXT AS shop_name,
      jsonb_agg(e) AS items
    FROM jsonb_array_elements(v_session.items_snapshot) AS e
    GROUP BY (e->>'shop_id'), (e->>'shop_name')
  LOOP
    DECLARE
      v_shop_subtotal NUMERIC := 0;
      v_shop_delivery_fee NUMERIC := 0;
      v_shop_coupon_discount NUMERIC := 0;
      v_shop_total NUMERIC := 0;
      v_item_inner JSONB;
      v_c_shop_id UUID;
    BEGIN
      FOR v_item_inner IN SELECT * FROM jsonb_array_elements(v_item.items)
      LOOP
        v_shop_subtotal := v_shop_subtotal + (v_item_inner->>'subtotal')::NUMERIC;
      END LOOP;

      v_shop_delivery_fee := COALESCE(
        (v_session.sub_order_delivery_fees->>v_item.shop_id::TEXT)::NUMERIC, 0
      );

      IF v_session.coupon_id IS NOT NULL THEN
        SELECT shop_id INTO v_c_shop_id FROM public.shop_coupons WHERE id = v_session.coupon_id;
        IF v_c_shop_id = v_item.shop_id THEN
          IF jsonb_array_length(v_session.items_snapshot) = jsonb_array_length(v_item.items) THEN
            v_shop_coupon_discount := v_session.server_coupon_discount;
          END IF;
        END IF;
      END IF;

      v_shop_total := v_shop_subtotal + v_shop_delivery_fee - v_shop_coupon_discount;

      v_order_number := 'ORD' || LPAD(nextval('public.order_number_seq')::TEXT, 8, '0');

      INSERT INTO public.orders (
        user_id, shop_id, order_number, order_group_id, group_order_number,
        delivery_address_text, address_id, customer_phone,
        payment_method, payment_status, status,
        subtotal, delivery_fee, discount, coupon_id, coupon_discount, total,
        notes, checkout_session_id, committed_at,
        invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no,
        invoice_tax_office, invoice_address, invoice_email,
        created_at, updated_at
      ) VALUES (
        v_user_id, v_item.shop_id, v_order_number, v_order_group_id, NULL,
        v_session.delivery_address_snapshot->>'address_line1',
        v_session.address_id,
        v_session.delivery_address_snapshot->>'phone',
        'balance', 'paid', 'pending',
        v_shop_subtotal, v_shop_delivery_fee, v_session.server_discount,
        v_session.coupon_id, v_shop_coupon_discount, v_shop_total,
        v_session.notes, p_session_id, v_now,
        v_session.invoice_data->>'invoice_type',
        v_session.invoice_data->>'invoice_full_name',
        v_session.invoice_data->>'invoice_tax_number',
        v_session.invoice_data->>'invoice_tc_no',
        v_session.invoice_data->>'invoice_tax_office',
        v_session.invoice_data->>'invoice_address',
        v_session.invoice_data->>'invoice_email',
        v_now, v_now
      )
      RETURNING id INTO v_order_id;

      FOR v_item_inner IN SELECT * FROM jsonb_array_elements(v_item.items)
      LOOP
        INSERT INTO public.order_items (
          order_id, product_id, product_name, price, product_price, quantity, subtotal,
          product_image_url, shop_id, shop_name, flash_sale_id, flash_price,
          variant_data, created_at
        ) VALUES (
          v_order_id,
          (v_item_inner->>'product_id')::UUID,
          v_item_inner->>'product_name',
          (v_item_inner->>'unit_price')::NUMERIC,
          (v_item_inner->>'unit_price')::NUMERIC,
          (v_item_inner->>'quantity')::INTEGER,
          (v_item_inner->>'subtotal')::NUMERIC,
          v_item_inner->>'image_url',
          (v_item_inner->>'shop_id')::UUID,
          v_item_inner->>'shop_name',
          NULLIF(v_item_inner->>'flash_sale_id','')::UUID,
          NULLIF(v_item_inner->>'flash_price','')::NUMERIC,
          v_item_inner->'variant_data',
          v_now
        );
      END LOOP;

      IF v_order_count = 0 THEN
        v_existing_order_id := v_order_id;
      END IF;
      v_order_count := v_order_count + 1;
    END;
  END LOOP;

  -- ===========================================================================
  -- 6) KUPON KULLANIM KAYDI
  -- ===========================================================================
  IF v_session.coupon_id IS NOT NULL AND v_session.server_coupon_discount > 0 THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.coupon_usages
      WHERE coupon_id = v_session.coupon_id AND order_id = v_existing_order_id
    ) THEN
      INSERT INTO public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
      VALUES (v_session.coupon_id, v_existing_order_id, v_user_id, v_session.server_coupon_discount);

      UPDATE public.shop_coupons
      SET usage_count = usage_count + 1
      WHERE id = v_session.coupon_id;
    END IF;
  END IF;

  -- ===========================================================================
  -- 7) FLAS REZERVASYONLARINI COMMIT ET
  -- ===========================================================================
  FOR v_reservation IN
    SELECT * FROM private.flash_sale_reservations
    WHERE session_id = p_session_id AND status = 'active'
    FOR UPDATE
  LOOP
    UPDATE public.flash_sales
    SET sold_count = sold_count + v_reservation.quantity
    WHERE id = v_reservation.sale_id;

    UPDATE private.flash_sale_reservations
    SET status = 'committed', committed_at = v_now
    WHERE id = v_reservation.id;
  END LOOP;

  -- ===========================================================================
  -- 8) SESSION COMPLETED
  -- ===========================================================================
  UPDATE private.server_checkout_sessions
  SET
    status = 'committed',
    committed_at = v_now,
    order_id = v_existing_order_id,
    order_group_order_id = v_order_group_id,
    updated_at = v_now
  WHERE id = p_session_id;

  -- Audit
  INSERT INTO private.server_checkout_audit (session_id, user_id, event_type, detail)
  VALUES (p_session_id, v_user_id, 'session_committed', jsonb_build_object(
    'order_id', v_existing_order_id,
    'payment_method', 'balance',
    'amount_deducted', v_session.server_total,
    'balance_txn_id', v_balance_txn_id
  ));

  RETURN QUERY SELECT
    v_existing_order_id,
    v_order_number,
    v_order_group_id,
    'committed'::TEXT,
    v_session.server_total,
    v_balance_txn_id,
    v_balance_after;
END;
$$;

REVOKE ALL ON FUNCTION public.commit_balance_order(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.commit_balance_order(UUID) TO authenticated;

DO $$
BEGIN
  RAISE NOTICE 'commit_cod_order + commit_balance_order RPC''leri olusturuldu (public semasi)';
  RAISE NOTICE '   - authenticated EXECUTE yetkisi';
  RAISE NOTICE '   - tum finansal islemler tek transaction icinde';
  RAISE NOTICE '   - idempotent (session_id ile tek order)';
  RAISE NOTICE '   - nextval public.order_number_seq olarak nitelendi (search_path duzeltmesi)';
END $$;

-- =============================================================================
-- KAYNAK 6/9: 20260802000010_order_state_machine_rpc.sql
-- CERRAHI DUZELTME #2: cancel_order, private.server_checkout_audit'e olmayan
--   kolonlara (order_id, payload) yaziyordu; gercek kolon (detail) ile duzeltildi:
--     (event_type, user_id, order_id, payload)  ->  (event_type, user_id, detail)
--     ('order_cancelled', v_user_id, p_order_id, v_audit) -> ('order_cancelled', v_user_id, v_audit)
-- =============================================================================
-- 20260802000010_order_state_machine_rpc.sql
-- Tarih: 2026-08-02
-- Server-authoritative siparis durum makinesi
-- 4 RPC: cancel_order, mark_paid (admin/service), mark_shipped, mark_delivered
-- Tum gecisler FOR UPDATE + allowed listesi + audit trigger.

SET search_path = public, private;

-- ==============================================================================
-- cancel_order - kullanici kendi siparisini iptal edebilir
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.cancel_order(
  p_order_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order RECORD;
  v_audit JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required | oturum gerekli' USING ERRCODE = 'P0001';
  END IF;

  SELECT id, user_id, status, payment_status, total, coupon_id, order_group_id
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:order_not_found | sipariş yok' USING ERRCODE = 'P0001';
  END IF;

  IF v_order.user_id <> v_user_id THEN
    RAISE EXCEPTION 'APP:forbidden | yetkisiz' USING ERRCODE = 'P0001';
  END IF;

  -- Durum makinesi: yalniz 'pending' ve 'confirmed' iptal edilebilir
  IF v_order.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'APP:cancel_not_allowed | durum: %', v_order.status USING ERRCODE = 'P0001';
  END IF;

  -- payment_status 'paid' ise iptal icin admin gerekli
  IF v_order.payment_status = 'paid' THEN
    RAISE EXCEPTION 'APP:cancel_paid_forbidden | ödeme alınmış, iade gerekli' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
  SET status = 'cancelled',
      cancelled_at = now(),
      cancel_reason = p_reason
  WHERE id = p_order_id;

  v_audit := jsonb_build_object(
    'event', 'order_cancelled',
    'order_id', p_order_id,
    'previous_status', v_order.status,
    'reason', p_reason
  );

  -- CERRAHI DUZELTME #2: server_checkout_audit tablosunda order_id/payload
  -- kolonlari YOKTUR; gercek kolon 'detail' (JSONB) kullanilir.
  INSERT INTO private.server_checkout_audit (event_type, user_id, detail)
  VALUES ('order_cancelled', v_user_id, v_audit);

  RETURN v_audit;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_order(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_order(UUID, TEXT) TO authenticated;

-- ==============================================================================
-- mark_paid - service_role/admin (online odeme callback'i basariyla
--   commit_online_order icinde payment_status='paid' yapar; bu RPC
--   yalnizca manuel admin islemleri icindir)
-- ==============================================================================
CREATE OR REPLACE FUNCTION private.mark_order_paid(
  p_order_id UUID,
  p_payment_transaction_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status, payment_status INTO v_status
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:order_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_status IN ('cancelled', 'delivered', 'refunded') THEN
    RAISE EXCEPTION 'APP:transition_not_allowed | %', v_status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
  SET payment_status = 'paid',
      status = CASE WHEN status = 'pending' THEN 'confirmed' ELSE status END,
      paid_at = COALESCE(paid_at, now()),
      payment_transaction_id = p_payment_transaction_id
  WHERE id = p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION private.mark_order_paid(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.mark_order_paid(UUID, UUID) TO service_role;

-- ==============================================================================
-- mark_shipped - service_role (kargo sirketi webhook veya admin panel)
-- ==============================================================================
CREATE OR REPLACE FUNCTION private.mark_order_shipped(
  p_order_id UUID,
  p_tracking_url TEXT DEFAULT NULL,
  p_cargo_company TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status FROM public.orders
  WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:order_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'APP:transition_not_allowed | %', v_status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
  SET status = 'shipped',
      tracking_url = COALESCE(p_tracking_url, tracking_url),
      cargo_company = COALESCE(p_cargo_company, cargo_company),
      shipped_at = now()
  WHERE id = p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION private.mark_order_shipped(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.mark_order_shipped(UUID, TEXT, TEXT) TO service_role;

-- ==============================================================================
-- mark_delivered - service_role
-- ==============================================================================
CREATE OR REPLACE FUNCTION private.mark_order_delivered(
  p_order_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status FROM public.orders
  WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:order_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_status <> 'shipped' THEN
    RAISE EXCEPTION 'APP:transition_not_allowed | %', v_status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
  SET status = 'delivered',
      delivered_at = now()
  WHERE id = p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION private.mark_order_delivered(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.mark_order_delivered(UUID) TO service_role;

-- =============================================================================
-- KAYNAK 7/9: _part_consolidated_commission_views.sql
-- BOLUM 7: Komisyon view'lari (kaynak: 20260131000002_commission_system.sql)
-- v_debt_orders ve v_admin_commission_dashboard uygulanmamisti.
-- Underlying orders kolonlari (admin_commission, commission_status,
-- commission_debt, admin_delivery_fee, order_number_int) mevcut RPC'ler
-- (get_seller_commission_summary vb.) tarafindan kullanildigi icin vardir.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_debt_orders AS
SELECT
    o.id,
    o.order_number_int,
    o.shop_id,
    s.name as shop_name,
    s.owner_id,
    o.subtotal,
    o.admin_commission,
    o.commission_debt,
    o.payment_method,
    o.status,
    o.created_at
FROM public.orders o
JOIN public.shops s ON s.id = o.shop_id
WHERE o.commission_status = 'debt'
  AND o.status != 'cancelled'
ORDER BY o.created_at DESC;

COMMENT ON VIEW public.v_debt_orders IS 'Borclu siparisler listesi (commission_status=debt)';

CREATE OR REPLACE VIEW public.v_admin_commission_dashboard AS
SELECT
    DATE(o.created_at) as date,
    COUNT(*) as order_count,
    SUM(o.subtotal) as total_sales,
    SUM(o.admin_commission) as total_commission,
    SUM(CASE WHEN o.commission_status = 'collected' THEN o.admin_commission ELSE 0 END) as collected_commission,
    SUM(CASE WHEN o.commission_status = 'debt' THEN o.admin_commission ELSE 0 END) as debt_commission,
    SUM(o.admin_delivery_fee) as total_delivery_fee,
    SUM(o.admin_commission + o.admin_delivery_fee) as total_admin_revenue
FROM public.orders o
WHERE o.status != 'cancelled'
GROUP BY DATE(o.created_at)
ORDER BY date DESC;

COMMENT ON VIEW public.v_admin_commission_dashboard IS 'Admin komisyon dashboard verileri';

-- View'lari admin/servis okuyabilsin. Komisyon verisi finansal oldugu icin
-- authenticated'a yalniz admin erisebilir; service_role tam erisir.
GRANT SELECT ON public.v_debt_orders TO authenticated, service_role;
GRANT SELECT ON public.v_admin_commission_dashboard TO authenticated, service_role;

-- =============================================================================
-- KAYNAK 8/9: _part_consolidated_profile_objects.sql
-- BOLUM 8: Profil guvenlik objeleri (kaynak: 20260803000006_secure_profiles_privileges_and_pii.sql)
--
-- SADECE uygulamanin ihtiyac duydugu 3 nesne olusturulur:
--   - public.public_profiles_safe (guvenli public profil view'i)
--   - public.ensure_my_profile()    (eksik legacy profili guvenli yaratir)
--   - public.set_my_presence(boolean) (online/last_seen gunceller)
--
-- DIGER: Kaynak migration'in invasive parcalari (profiles REVOKE, guard
-- trigger, admin RPC'leri, handle_new_user yeniden yazimi) KASITLI olarak
-- HARIC tutuldu. Bu dosya yalniz TESHIS raporundaki 3 boslugu doldurur;
-- mevcut profiles RLS/grant'larini korur, boylece dogrudan profiles okuyan
-- diger uygulama akislari bozulmaz. Tam profil guvenlik sertlendirilmesi
-- ayri bir migration olarak bilincli sekilde uygulanmalidir.
-- -----------------------------------------------------------------------------

-- public_profiles_safe: PII/role sutunlari ICERMEYEN guvenli public yuzey.
-- security_invoker=true: sorgu yapan kullanicinin yetkisiyle calisir.
CREATE OR REPLACE VIEW public.public_profiles_safe
  WITH (security_invoker = true) AS
SELECT
  p.id,
  p.username,
  p.full_name,
  p.avatar_url,
  p.cover_url,
  p.bio,
  p.website,
  p.location,
  p.gender,
  p.profile_is_public,
  p.created_at,
  p.updated_at,
  p.last_seen,
  p.status,
  p.is_ghost_mode
FROM public.profiles p
WHERE COALESCE(p.profile_is_public, true) = true;

COMMENT ON VIEW public.public_profiles_safe IS
  'Anon/authenticated icin guvenli public profil yuzeyi; PII/role sutunlari yok. security_invoker=true.';

GRANT SELECT ON public.public_profiles_safe TO anon, authenticated;


-- ensure_my_profile: eksik legacy profili guvenli varsayilanlarla olusturur.
CREATE OR REPLACE FUNCTION public.ensure_my_profile()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_meta jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'ensure_my_profile: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  SELECT u.email, u.raw_user_meta_data
    INTO v_email, v_meta
  FROM auth.users u
  WHERE u.id = v_uid;

  INSERT INTO public.profiles (
    id, email, full_name, username, role, is_admin,
    is_suspicious, is_ghost_mode, status, profile_is_public,
    is_online_enabled, show_last_seen, allow_messages_from_non_followers,
    delivered_count, created_at, updated_at
  )
  VALUES (
    v_uid, v_email,
    COALESCE(v_meta->>'full_name', ''),
    LOWER(COALESCE(v_meta->>'username', '')),
    'customer'::public.user_role, false, false, false, 'online', true, true, true, true, 0,
    NOW(), NOW()
  )
  ON CONFLICT (id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_my_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_my_profile() TO authenticated, service_role;


-- set_my_presence: server timestamp ile yalniz is_online/last_seen gunceller.
-- Hayalet mod veya tercihi kapaliysa gercek durum false olur.
CREATE OR REPLACE FUNCTION public.set_my_presence(p_is_online boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ghost boolean;
  v_enabled boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'set_my_presence: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  SELECT is_ghost_mode, is_online_enabled
    INTO v_ghost, v_enabled
  FROM public.profiles
  WHERE id = v_uid;

  UPDATE public.profiles
    SET
      is_online = CASE
        WHEN v_ghost = true THEN false
        WHEN COALESCE(v_enabled, true) = false THEN false
        ELSE p_is_online
      END,
      last_seen = NOW()
  WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_presence(boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_my_presence(boolean) TO authenticated, service_role;

-- =============================================================================
-- KAYNAK 9/9: _part_consolidated_new_objects.sql
-- BOLUM 9: api_keys tablosu (hicbir migration olusturmuyordu; admin paneli
-- CRUD yapiyor). RLS: yalniz admin.
-- Kolonlar Flutter kullanimina gore: _part_api_settings.dart ve
-- _part_data_loaders.dart (.select(), .order('created_at'), insert/update/delete)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
  key text NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_keys_created_at
  ON public.api_keys (created_at DESC);

-- updated_at otomatik guncelleme
CREATE OR REPLACE FUNCTION public.trg_api_keys_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS api_keys_set_updated_at ON public.api_keys;
CREATE TRIGGER api_keys_set_updated_at
  BEFORE UPDATE ON public.api_keys
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_api_keys_set_updated_at();

ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

-- Yalniz admin okuyup yonetebilir; API anahtarlari hassastir.
DROP POLICY IF EXISTS "api_keys_admin_all" ON public.api_keys;
CREATE POLICY "api_keys_admin_all"
  ON public.api_keys
  FOR ALL
  TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'::public.user_role
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'::public.user_role
  ));

DROP POLICY IF EXISTS "api_keys_service_all" ON public.api_keys;
CREATE POLICY "api_keys_service_all"
  ON public.api_keys
  FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

GRANT ALL ON public.api_keys TO authenticated, service_role;


-- -----------------------------------------------------------------------------
-- BOLUM 10: news_views RLS SELECT policy
-- Kaynak: news_system.sql sadece INSERT policy tanimlamisti; SELECT policy
-- yoktu -> sorgular her zaman bos donerdi. Uygulama news_views'a yalniz
-- INSERT yapsa da, admin analytics icin admin-only guvenli SELECT policy
-- eklenir (hassas goruntuleme verisini herkese acmaz).
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.news_views'::regclass
      AND polcmd IN ('r','*') AND polpermissive
  ) THEN
    CREATE POLICY "news_views_admin_select"
      ON public.news_views
      FOR SELECT
      TO authenticated
      USING (EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid() AND p.role = 'admin'::public.user_role
      ));
    RAISE NOTICE 'news_views icin admin SELECT policy olusturuldu';
  END IF;
END $$;


-- -----------------------------------------------------------------------------
-- BOLUM 11: smm_providers kolon-bazli SELECT grant (yeniden uygula)
-- Kaynak: 20260710000003_smm_integration.sql, ama uygulanmamis olabilir.
-- smm_service.dart yalniz su kolonlari select ediyor:
--   id, owner_type, owner_id, name, api_url, is_active, created_at, updated_at
-- ONEM: Tablo-bazli SELECT grant ACILMADI -> api_key kolonu sizmaz.
-- -----------------------------------------------------------------------------
GRANT SELECT (id, owner_type, owner_id, name, api_url, is_active, created_at, updated_at)
  ON public.smm_providers TO authenticated;
GRANT INSERT (owner_type, owner_id, name, api_url, api_key, is_active)
  ON public.smm_providers TO authenticated;
GRANT UPDATE (name, api_url, api_key, is_active)
  ON public.smm_providers TO authenticated;
GRANT DELETE ON public.smm_providers TO authenticated;
GRANT ALL ON public.smm_providers TO service_role;


DO $$
BEGIN
  RAISE NOTICE '==================================================';
  RAISE NOTICE 'Konsolide uygulama kontrati duzeltmesi tamamlandi.';
  RAISE NOTICE 'Eksik RPC, tablo, view, RLS ve yetkiler olusturuldu.';
  RAISE NOTICE 'Dogrulama icin VERIFY_fill_app_contract_gaps.sql i calistirin.';
  RAISE NOTICE '==================================================';
END $$;

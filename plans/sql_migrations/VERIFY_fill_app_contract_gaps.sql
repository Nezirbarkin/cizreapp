-- =============================================================================
-- VERIFY_fill_app_contract_gaps.sql
-- =============================================================================
-- 20260804000002_fill_app_contract_gaps.sql uygulandiktan SONRA calistirilir.
-- Teşhis raporundaki tüm eksikliklerin giderilip giderilmedigini kontrol eder.
-- Her satir: kontrol adi + durum (OK / EKSIK) + ek bilgi.
-- Tum satirlar 'OK' olmali; 'EKSIK' varsa ilgili nesne düzeltilmemis demektir.
-- =============================================================================

WITH checks AS (
  -- ---- 7 eksik RPC (public semasinda olmali) ----
  SELECT 'RPC: admin_reward_points_overview' AS ad, EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_reward_points_overview'
  ) AS ok, '' AS bilgi
  UNION ALL SELECT 'RPC: cancel_order', EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'cancel_order'
  ), ''
  UNION ALL SELECT 'RPC: commit_balance_order', EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'commit_balance_order'
  ), ''
  UNION ALL SELECT 'RPC: commit_cod_order', EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'commit_cod_order'
  ), ''
  UNION ALL SELECT 'RPC: ensure_my_profile', EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'ensure_my_profile'
  ), ''
  UNION ALL SELECT 'RPC: prepare_checkout_session', EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'prepare_checkout_session'
  ), ''
  UNION ALL SELECT 'RPC: set_my_presence', EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'set_my_presence'
  ), ''

  -- ---- private semasinda KALMAMALI (PostgREST acmaz) ----
  UNION ALL SELECT 'RPC private.degil: prepare_checkout_session public''ta', EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'prepare_checkout_session'
  ), 'public''ta olmali'

  -- ---- Tablo / View varlik ----
  UNION ALL SELECT 'TABLO: api_keys', EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'api_keys'
  ), ''
  UNION ALL SELECT 'TABLO: user_point_accounts', EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'user_point_accounts'
  ), ''
  UNION ALL SELECT 'TABLO: reward_points_public_config', EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'reward_points_public_config'
  ), ''
  UNION ALL SELECT 'VIEW: my_point_ledger_entries', EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'public' AND table_name = 'my_point_ledger_entries'
  ), ''
  UNION ALL SELECT 'VIEW: my_ad_reward_sessions', EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'public' AND table_name = 'my_ad_reward_sessions'
  ), ''
  UNION ALL SELECT 'VIEW: public_profiles_safe', EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'public' AND table_name = 'public_profiles_safe'
  ), ''
  UNION ALL SELECT 'VIEW: v_admin_commission_dashboard', EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'public' AND table_name = 'v_admin_commission_dashboard'
  ), ''
  UNION ALL SELECT 'VIEW: v_debt_orders', EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'public' AND table_name = 'v_debt_orders'
  ), ''

  -- ---- Sequence (commit_*_order nextval kullanir) ----
  UNION ALL SELECT 'SEQ: order_number_seq', EXISTS (
    SELECT 1 FROM pg_sequences WHERE schemaname = 'public' AND sequencename = 'order_number_seq'
  ), ''

  -- ---- cancel_order audit düzeltmesi: server_checkout_audit 'detail' kolonu olmali,
  --      'order_id'/'payload' OLMAMALI ----
  UNION ALL SELECT 'AUDIT kolon: server_checkout_audit.detail VAR', EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'private' AND table_name = 'server_checkout_audit'
      AND column_name = 'detail'
  ), ''
  UNION ALL SELECT 'AUDIT kolon: server_checkout_audit.order_id YOK', NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'private' AND table_name = 'server_checkout_audit'
      AND column_name = 'order_id'
  ), 'olmamali'

  -- ---- news_views: SELECT policy olmali ----
  UNION ALL SELECT 'RLS: news_views SELECT policy', EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.news_views'::regclass
      AND polcmd IN ('r','*')
  ), ''

  -- ---- smm_providers: kolon-bazli SELECT grant (api_key sızmasin) ----
  UNION ALL SELECT 'GRANT: smm_providers kolon SELECT', EXISTS (
    SELECT 1 FROM information_schema.column_privileges
    WHERE table_schema = 'public' AND table_name = 'smm_providers'
      AND grantee = 'authenticated' AND privilege_type = 'SELECT'
  ), ''
)
SELECT
  ad AS "Kontrol",
  CASE WHEN ok THEN 'OK' ELSE 'EKSIK' END AS "Durum",
  bilgi AS "Bilgi"
FROM checks
ORDER BY CASE WHEN ok THEN 1 ELSE 0 END, ad;
-- EKSIK satirlar üste cikar (ok=false -> 0).

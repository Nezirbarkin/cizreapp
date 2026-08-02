-- 20260802000012_audit_views.sql
-- Tarih: 2026-08-02
-- Sadece service_role tarafından okunabilen denetim görünümleri.

SET search_path = public, private;

-- ════════════════════════════════════════════════════════════════════════
-- v_session_amount_mismatch
-- Server'da hesaplanan toplam ile iyzico paidPrice uyuşmayan session'lar
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW private.v_session_amount_mismatch AS
SELECT
  s.id AS session_id,
  s.user_id,
  s.payment_method,
  s.server_total,
  s.expected_paid_price,
  pt.id AS payment_transaction_id,
  pt.payment_status,
  pt.iyzico_paid_price,
  pt.iyzico_currency,
  pt.reconciliation_status,
  pt.reconciliation_note,
  pt.error_code,
  pt.error_message,
  pt.created_at
FROM private.server_checkout_sessions s
LEFT JOIN public.payment_transactions pt
  ON pt.checkout_session_id = s.id
WHERE
  s.expected_paid_price IS NOT NULL
  AND pt.iyzico_paid_price IS NOT NULL
  AND ABS(CAST(s.expected_paid_price AS NUMERIC) - CAST(pt.iyzico_paid_price AS NUMERIC)) > 0.005;

REVOKE ALL ON private.v_session_amount_mismatch FROM PUBLIC, anon, authenticated;
GRANT SELECT ON private.v_session_amount_mismatch TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- v_pending_stale_sessions
-- 15dk'dan eski henüz tamamlanmamış session'lar (cron temizler)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW private.v_pending_stale_sessions AS
SELECT
  id, user_id, status, server_total, payment_method,
  created_at, expires_at
FROM private.server_checkout_sessions
WHERE status = 'active'
  AND expires_at < now();

REVOKE ALL ON private.v_pending_stale_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON private.v_pending_stale_sessions TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- v_coupon_exhausted
-- usage_limit'i aşılmış kuponlar
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW private.v_coupon_exhausted AS
SELECT
  c.id, c.code, c.usage_limit, c.used_count,
  c.discount_type, c.discount_value,
  c.start_date, c.end_date, c.is_active
FROM public.coupons c
WHERE c.usage_limit IS NOT NULL
  AND c.used_count >= c.usage_limit;

REVOKE ALL ON private.v_coupon_exhausted FROM PUBLIC, anon, authenticated;
GRANT SELECT ON private.v_coupon_exhausted TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- v_failed_payments_today
-- Bugün başarısız olan payment_transactions (monitoring)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW private.v_failed_payments_today AS
SELECT
  pt.id, pt.user_id, pt.iyzico_paid_price, pt.iyzico_currency,
  pt.error_code, pt.error_message, pt.error_group,
  pt.reconciliation_status,
  pt.created_at
FROM public.payment_transactions pt
WHERE pt.payment_status IN ('failure', 'mismatch')
  AND pt.created_at >= (now() - INTERVAL '24 hours');

REVOKE ALL ON private.v_failed_payments_today FROM PUBLIC, anon, authenticated;
GRANT SELECT ON private.v_failed_payments_today TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- v_recent_audit_events
-- Son 24 saatteki tüm denetim olayları
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW private.v_recent_audit_events AS
SELECT
  id, event_type, user_id, order_id, payment_transaction_id,
  amount, payload, created_at
FROM private.server_checkout_audit
WHERE created_at >= (now() - INTERVAL '24 hours');

REVOKE ALL ON private.v_recent_audit_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON private.v_recent_audit_events TO service_role;

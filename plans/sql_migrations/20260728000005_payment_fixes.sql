-- =====================================================
-- DOSYA: supabase/migrations/20260728000005_payment_fixes.sql
-- AMAÇ: Payment + balance güvenlik + rate limit
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. payment_status enum kontrol
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status_enum') THEN
    CREATE TYPE payment_status_enum AS ENUM ('pending', 'success', 'failure', 'cancelled', 'error');
  END IF;
END $$;

-- 2. payment_transactions tablosunda order_id kolonu
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'payment_transactions' AND column_name = 'order_id'
  ) THEN
    ALTER TABLE payment_transactions ADD COLUMN order_id UUID REFERENCES orders(id);
  END IF;
END $$;

-- 3. payment_transactions + order_id unique (idempotency)
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_transactions_order_id
  ON payment_transactions(order_id) WHERE order_id IS NOT NULL;

-- 4. Balance RPC güvenlik - auth kontrolü ile
CREATE OR REPLACE FUNCTION use_balance_for_order(
  p_order_id UUID,
  p_amount NUMERIC,
  p_order_total NUMERIC
)
RETURNS TABLE (
  transaction_id UUID,
  amount_paid NUMERIC,
  remaining_amount NUMERIC,
  new_balance NUMERIC,
  is_fully_paid BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_current_balance NUMERIC;
  v_amount_paid NUMERIC;
  v_new_balance NUMERIC;
  v_remaining NUMERIC;
  v_txn_id UUID;
BEGIN
  -- Auth kontrol
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;

  -- Sipariş sahibi kontrol
  IF NOT EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Order not found or not authorized' USING ERRCODE = '42501';
  END IF;

  -- Mevcut bakiye
  SELECT balance INTO v_current_balance
  FROM user_balances
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_current_balance IS NULL THEN
    v_current_balance := 0;
  END IF;

  -- Hesapla
  v_amount_paid := LEAST(p_amount, v_current_balance);
  v_remaining := p_order_total - v_amount_paid;
  v_new_balance := v_current_balance - v_amount_paid;

  -- Bakiye düş
  IF v_amount_paid > 0 THEN
    UPDATE user_balances
    SET balance = v_new_balance, updated_at = NOW()
    WHERE user_id = v_user_id;

    -- Transaction kaydı
    INSERT INTO balance_transactions (
      user_id, amount, fee, type, reference_type, reference_id, description
    ) VALUES (
      v_user_id, v_amount_paid, 0, 'order_payment', 'order', p_order_id,
      'Sipariş ödemesi: ' || p_order_id::TEXT
    )
    RETURNING id INTO v_txn_id;
  END IF;

  -- Order güncelle
  UPDATE orders
  SET payment_status = CASE WHEN v_remaining <= 0 THEN 'paid' ELSE 'partial' END,
      updated_at = NOW()
  WHERE id = p_order_id;

  RETURN QUERY SELECT
    v_txn_id, v_amount_paid, v_remaining, v_new_balance, (v_remaining <= 0);
END;
$$;

REVOKE ALL ON FUNCTION use_balance_for_order(UUID, NUMERIC, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION use_balance_for_order(UUID, NUMERIC, NUMERIC) TO authenticated, service_role;

-- 5. Withdrawal rate limit
CREATE TABLE IF NOT EXISTS withdrawal_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  amount NUMERIC NOT NULL,
  status TEXT NOT NULL,
  error_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_withdrawal_attempts_user_created
  ON withdrawal_attempts(user_id, created_at DESC);

-- 6. Daily withdrawal limit
CREATE OR REPLACE FUNCTION check_withdrawal_limit(p_user_id UUID, p_amount NUMERIC)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  v_today_total NUMERIC;
  v_daily_limit NUMERIC := 50000;
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO v_today_total
  FROM withdrawal_attempts
  WHERE user_id = p_user_id
    AND status = 'success'
    AND created_at >= CURRENT_DATE;

  RETURN (v_today_total + p_amount) <= v_daily_limit;
END;
$$;

REVOKE ALL ON FUNCTION check_withdrawal_limit(UUID, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION check_withdrawal_limit(UUID, NUMERIC) TO authenticated, service_role;

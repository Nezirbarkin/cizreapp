-- =====================================================
-- DOSYA: supabase/migrations/20260728000010_smm_fixes.sql
-- AMAÇ: SMM provider RLS + rate limit
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. SMM provider RLS (smm_providers.shop_id yok, owner_id var)
DROP POLICY IF EXISTS "Sellers manage own providers" ON smm_providers;
CREATE POLICY "Sellers manage own providers" ON smm_providers
  FOR ALL TO authenticated
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS "Admins manage all providers" ON smm_providers;
CREATE POLICY "Admins manage all providers" ON smm_providers
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 2. Digital orders RLS
DROP POLICY IF EXISTS "Users view own digital orders" ON digital_orders;
CREATE POLICY "Users view own digital orders" ON digital_orders
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Sellers view shop digital orders" ON digital_orders;
CREATE POLICY "Sellers view shop digital orders" ON digital_orders
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM smm_providers sp
      WHERE sp.id = digital_orders.provider_id AND sp.owner_id = auth.uid()
    )
  );

-- 3. SMM rate limit tablosu
CREATE TABLE IF NOT EXISTS smm_rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id UUID NOT NULL REFERENCES smm_providers(id),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  request_count INTEGER DEFAULT 1,
  window_start TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_smm_rate_limits_provider_user
  ON smm_rate_limits (provider_id, user_id, created_at DESC);

-- 4. Rate limit check fonksiyonu
CREATE OR REPLACE FUNCTION check_smm_rate_limit(
  p_provider_id UUID,
  p_user_id UUID,
  p_max_requests INTEGER DEFAULT 10,
  p_window_minutes INTEGER DEFAULT 1
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM smm_rate_limits
  WHERE provider_id = p_provider_id
    AND user_id = p_user_id
    AND created_at >= NOW() - (p_window_minutes || ' minutes')::INTERVAL;

  RETURN v_count < p_max_requests;
END;
$$;

REVOKE ALL ON FUNCTION check_smm_rate_limit(UUID, UUID, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION check_smm_rate_limit(UUID, UUID, INTEGER, INTEGER) TO authenticated, service_role;

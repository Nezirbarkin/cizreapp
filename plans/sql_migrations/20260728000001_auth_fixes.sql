-- =====================================================
-- DOSYA: supabase/migrations/20260728000001_auth_fixes.sql
-- AMAÇ: Auth username case-insensitive + login tracking
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. Username unique constraint case-insensitive yap
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_username_unique;
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_username_lower
  ON profiles (LOWER(username))
  WHERE username IS NOT NULL;

-- 2. Username arama fonksiyonu (case-insensitive)
CREATE OR REPLACE FUNCTION get_email_by_username(p_username TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT;
BEGIN
  SELECT email INTO v_email
  FROM profiles
  WHERE LOWER(username) = LOWER(p_username)
  LIMIT 1;

  RETURN v_email;
END;
$$;

REVOKE ALL ON FUNCTION get_email_by_username(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_email_by_username(TEXT) TO authenticated;

-- 3. Login denemesi log tablosu (güvenlik için)
CREATE TABLE IF NOT EXISTS login_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email_or_username TEXT NOT NULL,
  ip_address INET,
  user_agent TEXT,
  success BOOLEAN DEFAULT FALSE,
  failure_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_email ON login_attempts (LOWER(email_or_username), created_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_attempts_created ON login_attempts (created_at DESC);

-- RLS: sadece service_role görebilir (ama kendi denemesini)
ALTER TABLE login_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own login attempts" ON login_attempts;
CREATE POLICY "Users can view own login attempts" ON login_attempts
  FOR SELECT TO authenticated
  USING (LOWER(email_or_username) = LOWER((SELECT email FROM auth.users WHERE id = auth.uid())));

-- 4. Test query
-- SELECT get_email_by_username('testuser');
-- SELECT * FROM login_attempts LIMIT 5;

-- registration_otps tablosu
CREATE TABLE IF NOT EXISTS registration_otps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    code TEXT NOT NULL,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ
);

-- Index
CREATE INDEX IF NOT EXISTS idx_registration_otps_email ON registration_otps(email);
CREATE INDEX IF NOT EXISTS idx_registration_otps_code ON registration_otps(code);

-- RLS
ALTER TABLE registration_otps ENABLE ROW LEVEL SECURITY;

-- Policy: once sil, sonra olustur (idempotent)
DROP POLICY IF EXISTS "Service role full access on registration_otps" ON registration_otps;
CREATE POLICY "Service role full access on registration_otps" ON registration_otps
    FOR ALL TO service_role USING (true);

-- verify_registration_otp RPC fonksiyonu
CREATE OR REPLACE FUNCTION verify_registration_otp(p_email TEXT, p_code TEXT)
RETURNS JSON AS $$
DECLARE
    v_otp RECORD;
    v_result JSON;
BEGIN
    -- OTP'yi bul
    SELECT * INTO v_otp FROM registration_otps
    WHERE email = LOWER(p_email)
      AND code = p_code
      AND verified = FALSE
      AND expires_at > NOW()
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_otp IS NULL THEN
        RETURN json_build_object(
            'success', FALSE,
            'message', 'Geçersiz veya süresi dolmuş kod'
        );
    END IF;

    -- OTP'yi kullanildi olarak isaretle
    UPDATE registration_otps
    SET verified = TRUE, used_at = NOW()
    WHERE id = v_otp.id;

    RETURN json_build_object(
        'success', TRUE,
        'message', 'E-posta doğrulandı',
        'verified_email', p_email
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- password_reset_otps tablosu
CREATE TABLE IF NOT EXISTS password_reset_otps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    code TEXT NOT NULL,
    used BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_password_reset_otps_email ON password_reset_otps(email);

ALTER TABLE password_reset_otps ENABLE ROW LEVEL SECURITY;

-- Policy: once sil, sonra olustur (idempotent)
DROP POLICY IF EXISTS "Service role full access on password_reset_otps" ON password_reset_otps;
CREATE POLICY "Service role full access on password_reset_otps" ON password_reset_otps
    FOR ALL TO service_role USING (true);

-- verify_password_reset_otp RPC fonksiyonu
CREATE OR REPLACE FUNCTION verify_password_reset_otp(p_email TEXT, p_code TEXT)
RETURNS JSON AS $$
DECLARE
    v_otp RECORD;
BEGIN
    SELECT * INTO v_otp FROM password_reset_otps
    WHERE email = LOWER(p_email)
      AND code = p_code
      AND used = FALSE
      AND expires_at > NOW()
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_otp IS NULL THEN
        RETURN json_build_object(
            'success', FALSE,
            'message', 'Geçersiz veya süresi dolmuş kod'
        );
    END IF;

    UPDATE password_reset_otps
    SET used = TRUE, used_at = NOW()
    WHERE id = v_otp.id;

    RETURN json_build_object(
        'success', TRUE,
        'message', 'Kod doğrulandı',
        'verified_email', p_email
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

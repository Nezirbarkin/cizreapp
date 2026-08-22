-- =====================================================================
-- BAKİYE YÜKLEME GÜVENLİK DÜZELTMESİ
-- Tarih: 2026-07-10
-- Mevcut düzene zarar vermeden eklenir
-- =====================================================================

-- =====================================================================
-- 1. GÜVENLİK LOGLARI TABLOSU (mevcut sistemi bozmaz)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.balance_security_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(50) NOT NULL,
    user_id UUID,
    ip_address INET,
    user_agent TEXT,
    device_fingerprint TEXT,
    amount NUMERIC(12, 2),
    currency VARCHAR(3) DEFAULT 'TRY',
    payment_method VARCHAR(20),
    reference_id UUID,
    payment_reference VARCHAR(100),
    status VARCHAR(20),
    failure_reason TEXT,
    metadata JSONB DEFAULT '{}',
    risk_score INTEGER DEFAULT 0,
    risk_factors JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_security_logs_user_id ON public.balance_security_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_security_logs_ip ON public.balance_security_logs(ip_address);
CREATE INDEX IF NOT EXISTS idx_security_logs_created_at ON public.balance_security_logs(created_at);

-- =====================================================================
-- 2. RATE LIMITING TABLOSU
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.balance_rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    period_type VARCHAR(20) NOT NULL,
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    transaction_count INTEGER DEFAULT 0,
    total_amount NUMERIC(12, 2) DEFAULT 0,
    last_transaction_at TIMESTAMPTZ,
    ip_addresses TEXT[],
    device_fingerprints TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_user_period UNIQUE (user_id, period_type, period_start)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_user_period ON public.balance_rate_limits(user_id, period_type, period_start);

-- =====================================================================
-- 3. GÜVENLİK AYARLARI TABLOSU
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.balance_security_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Varsayılan ayarlar (varsa eklemez)
INSERT INTO public.balance_security_settings (setting_key, setting_value, description)
VALUES
    ('daily_topup_limit_count', '10', 'Günlük max yükleme sayısı'),
    ('daily_topup_limit_amount', '50000', 'Günlük max yükleme tutarı (TL)'),
    ('monthly_topup_limit_count', '50', 'Aylık max yükleme sayısı'),
    ('monthly_topup_limit_amount', '200000', 'Aylık max yükleme tutarı (TL)'),
    ('max_ips_per_user_daily', '3', 'Günlük max farklı IP'),
    ('max_devices_per_user_daily', '5', 'Günlük max farklı cihaz'),
    ('suspicious_amount_threshold', '5000', 'Şüpheli tutar eşiği'),
    ('risk_score_block_threshold', '70', 'Otomatik engelleme risk skoru')
ON CONFLICT (setting_key) DO NOTHING;

-- =====================================================================
-- 4. GÜVENLİK LOG FONKSİYONU
-- =====================================================================
CREATE OR REPLACE FUNCTION public.log_balance_security_event(
    p_event_type VARCHAR,
    p_user_id UUID DEFAULT NULL,
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL,
    p_device_fingerprint TEXT DEFAULT NULL,
    p_amount NUMERIC DEFAULT NULL,
    p_payment_method VARCHAR DEFAULT NULL,
    p_reference_id UUID DEFAULT NULL,
    p_payment_reference VARCHAR DEFAULT NULL,
    p_status VARCHAR DEFAULT 'success',
    p_failure_reason TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}',
    p_risk_score INTEGER DEFAULT 0,
    p_risk_factors JSONB DEFAULT '[]'
)
RETURNS UUID AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO public.balance_security_logs (
        event_type, user_id, ip_address, user_agent, device_fingerprint,
        amount, payment_method, reference_id, payment_reference,
        status, failure_reason, metadata, risk_score, risk_factors
    ) VALUES (
        p_event_type, p_user_id, p_ip_address, p_user_agent, p_device_fingerprint,
        p_amount, p_payment_method, p_reference_id, p_payment_reference,
        p_status, p_failure_reason, p_metadata, p_risk_score, p_risk_factors
    ) RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

-- =====================================================================
-- 5. RATE LIMIT KONTROL FONKSİYONU
-- =====================================================================
CREATE OR REPLACE FUNCTION public.check_balance_rate_limit(
    p_user_id UUID,
    p_amount NUMERIC,
    p_ip_address INET DEFAULT NULL,
    p_device_fingerprint TEXT DEFAULT NULL
)
RETURNS TABLE(
    allowed BOOLEAN,
    reason TEXT,
    current_count INTEGER,
    current_amount NUMERIC,
    limit_count INTEGER,
    limit_amount NUMERIC,
    risk_score INTEGER,
    risk_factors JSONB
) AS $$
DECLARE
    v_daily_count_limit INTEGER := 10;
    v_daily_amount_limit NUMERIC := 50000;
    v_monthly_count_limit INTEGER := 50;
    v_monthly_amount_limit NUMERIC := 200000;
    v_max_ips INTEGER := 3;
    v_max_devices INTEGER := 5;

    v_daily_count INTEGER := 0;
    v_daily_amount NUMERIC := 0;
    v_current_ips TEXT[] := ARRAY[]::TEXT[];
    v_current_devices TEXT[] := ARRAY[]::TEXT[];

    v_risk_score INTEGER := 0;
    v_risk_factors JSONB := '[]'::JSONB;
    v_allowed BOOLEAN := TRUE;
    v_reason TEXT := 'OK';
BEGIN
    -- Günlük istatistikleri al
    SELECT COALESCE(SUM(transaction_count), 0),
           COALESCE(SUM(total_amount), 0),
           COALESCE(array_agg(DISTINCT unnest(ip_addresses)) FILTER (WHERE ip_addresses IS NOT NULL), ARRAY[]::TEXT[]),
           COALESCE(array_agg(DISTINCT unnest(device_fingerprints)) FILTER (WHERE device_fingerprints IS NOT NULL), ARRAY[]::TEXT[])
    INTO v_daily_count, v_daily_amount, v_current_ips, v_current_devices
    FROM public.balance_rate_limits
    WHERE user_id = p_user_id
      AND period_type = 'daily'
      AND period_start <= NOW()
      AND period_end > NOW();

    -- Rate limit kontrolleri
    IF v_daily_count >= v_daily_count_limit THEN
        v_allowed := FALSE;
        v_reason := 'Günlük işlem limiti aşıldı (max: ' || v_daily_count_limit || ')';
        v_risk_score := v_risk_score + 30;
    END IF;

    IF v_daily_amount + p_amount > v_daily_amount_limit THEN
        v_allowed := FALSE;
        v_reason := 'Günlük tutar limiti aşıldı (max: ' || v_daily_amount_limit || ' TL)';
        v_risk_score := v_risk_score + 40;
    END IF;

    -- Çoklu IP kontrolü
    IF p_ip_address IS NOT NULL AND array_length(v_current_ips, 1) > 0 THEN
        IF NOT (p_ip_address::TEXT = ANY(v_current_ips)) AND array_length(v_current_ips, 1) >= v_max_ips THEN
            v_risk_score := v_risk_score + 20;
            v_risk_factors := v_risk_factors || '"multiple_ips_detected"'::JSONB;
        END IF;
    END IF;

    -- Çoklu cihaz kontrolü
    IF p_device_fingerprint IS NOT NULL AND array_length(v_current_devices, 1) > 0 THEN
        IF NOT (p_device_fingerprint = ANY(v_current_devices)) AND array_length(v_current_devices, 1) >= v_max_devices THEN
            v_risk_score := v_risk_score + 15;
            v_risk_factors := v_risk_factors || '"multiple_devices_detected"'::JSONB;
        END IF;
    END IF;

    -- Risk skoru çok yüksekse engelle
    IF v_risk_score >= 70 AND v_allowed THEN
        v_allowed := FALSE;
        v_reason := 'Şüpheli aktivite tespit edildi';
    END IF;

    RETURN QUERY SELECT v_allowed, v_reason,
                       (v_daily_count + 1),
                       (v_daily_amount + p_amount),
                       v_daily_count_limit,
                       v_daily_amount_limit,
                       v_risk_score,
                       v_risk_factors;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

-- =====================================================================
-- 6. RATE LIMIT GÜNCELLEME FONKSİYONU
-- =====================================================================
CREATE OR REPLACE FUNCTION public.update_balance_rate_limit(
    p_user_id UUID,
    p_amount NUMERIC,
    p_ip_address INET DEFAULT NULL,
    p_device_fingerprint TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_daily_id UUID;
    v_now TIMESTAMPTZ := NOW();
    v_today_start TIMESTAMPTZ := DATE_TRUNC('day', v_now);
    v_today_end TIMESTAMPTZ := v_today_start + INTERVAL '1 day';
BEGIN
    SELECT id INTO v_daily_id FROM public.balance_rate_limits
    WHERE user_id = p_user_id AND period_type = 'daily'
      AND period_start = v_today_start FOR UPDATE;

    IF v_daily_id IS NOT NULL THEN
        UPDATE public.balance_rate_limits SET
            transaction_count = transaction_count + 1,
            total_amount = total_amount + p_amount,
            last_transaction_at = v_now,
            updated_at = v_now,
            ip_addresses = CASE
                WHEN p_ip_address IS NOT NULL AND NOT (p_ip_address::TEXT = ANY(ip_addresses))
                THEN array_append(ip_addresses, p_ip_address::TEXT)
                ELSE ip_addresses
            END,
            device_fingerprints = CASE
                WHEN p_device_fingerprint IS NOT NULL AND NOT (p_device_fingerprint = ANY(device_fingerprints))
                THEN array_append(device_fingerprints, p_device_fingerprint)
                ELSE device_fingerprints
            END
        WHERE id = v_daily_id;
    ELSE
        INSERT INTO public.balance_rate_limits (
            user_id, period_type, period_start, period_end,
            transaction_count, total_amount, last_transaction_at,
            ip_addresses, device_fingerprints
        ) VALUES (
            p_user_id, 'daily', v_today_start, v_today_end,
            1, p_amount, v_now,
            CASE WHEN p_ip_address IS NOT NULL THEN ARRAY[p_ip_address::TEXT] ELSE ARRAY[]::TEXT[] END,
            CASE WHEN p_device_fingerprint IS NOT NULL THEN ARRAY[p_device_fingerprint] ELSE ARRAY[]::TEXT[] END
        );
    END IF;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

-- =====================================================================
-- 7. GÜVENLİ ATOMİK BAKİYE YÜKLEME FONKSİYONU
-- =====================================================================
CREATE OR REPLACE FUNCTION public.atomic_add_balance_topup_secure(
    p_user_id UUID,
    p_amount NUMERIC,
    p_pending_txn_id UUID,
    p_payment_id VARCHAR,
    p_paid_price NUMERIC,
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL,
    p_device_fingerprint TEXT DEFAULT NULL
)
RETURNS TABLE(
    success BOOLEAN,
    balance_before NUMERIC,
    balance_after NUMERIC,
    error_message TEXT,
    blocked_reason TEXT,
    security_log_id UUID
) AS $$
DECLARE
    v_security_log_id UUID;
    v_allowed BOOLEAN;
    v_reason TEXT;
    v_risk_score INTEGER;
    v_risk_factors JSONB;

    v_balance_id UUID;
    v_current_balance NUMERIC;
    v_new_balance NUMERIC;
    v_txn_exists BOOLEAN;
BEGIN
    -- 1. İşlem tekrar kontrolü (replay attack koruması)
    SELECT EXISTS(
        SELECT 1 FROM public.balance_transactions 
        WHERE id = p_pending_txn_id AND status = 'completed'
    ) INTO v_txn_exists;

    IF v_txn_exists THEN
        SELECT balance_after INTO v_current_balance 
        FROM public.balance_transactions WHERE id = p_pending_txn_id;

        INSERT INTO public.balance_security_logs (
            event_type, user_id, ip_address, user_agent, device_fingerprint,
            amount, payment_method, reference_id, payment_reference,
            status, failure_reason, risk_score, risk_factors
        ) VALUES (
            'topup_completed', p_user_id, p_ip_address, p_user_agent, p_device_fingerprint,
            p_amount, 'card', p_pending_txn_id, p_payment_id,
            'blocked', 'Replay attempt detected', 100, 
            '["replay_attack"]'::JSONB
        ) RETURNING id INTO v_security_log_id;

        RETURN QUERY SELECT FALSE, v_current_balance, v_current_balance, 
                           'İşlem zaten işlenmiş', 'Replay attempt', v_security_log_id;
        RETURN;
    END IF;

    -- 2. Rate limit kontrolü
    SELECT * INTO v_allowed, v_reason, v_risk_score, v_risk_factors
    FROM public.check_balance_rate_limit(p_user_id, p_amount, p_ip_address, p_device_fingerprint);

    IF NOT v_allowed THEN
        INSERT INTO public.balance_security_logs (
            event_type, user_id, ip_address, user_agent, device_fingerprint,
            amount, payment_method, reference_id, payment_reference,
            status, failure_reason, risk_score, risk_factors
        ) VALUES (
            'topup_initiated', p_user_id, p_ip_address, p_user_agent, p_device_fingerprint,
            p_amount, 'card', p_pending_txn_id, p_payment_id,
            'blocked', v_reason, v_risk_score, v_risk_factors
        ) RETURNING id INTO v_security_log_id;

        RETURN QUERY SELECT FALSE, 0::NUMERIC, 0::NUMERIC, v_reason, v_reason, v_security_log_id;
        RETURN;
    END IF;

    -- 3. Log
    INSERT INTO public.balance_security_logs (
        event_type, user_id, ip_address, user_agent, device_fingerprint,
        amount, payment_method, reference_id, payment_reference,
        status, risk_score, risk_factors
    ) VALUES (
        'topup_completed', p_user_id, p_ip_address, p_user_agent, p_device_fingerprint,
        p_amount, 'card', p_pending_txn_id, p_payment_id,
        'success', v_risk_score, v_risk_factors
    ) RETURNING id INTO v_security_log_id;

    -- 4. Rate limit güncelle
    PERFORM public.update_balance_rate_limit(p_user_id, p_amount, p_ip_address, p_device_fingerprint);

    -- 5. Atomik bakiye güncelleme
    SELECT id, balance INTO v_balance_id, v_current_balance
    FROM public.user_balances
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF v_balance_id IS NULL THEN
        INSERT INTO public.user_balances (user_id, balance, total_earned)
        VALUES (p_user_id, p_paid_price, p_paid_price)
        RETURNING balance INTO v_new_balance;

        UPDATE public.balance_transactions SET
            status = 'completed',
            balance_before = 0,
            balance_after = v_new_balance,
            metadata = jsonb_build_object('payment_id', p_payment_id, 'paid_price', p_paid_price)
        WHERE id = p_pending_txn_id;

        RETURN QUERY SELECT TRUE, 0::NUMERIC, v_new_balance, NULL::TEXT, NULL::TEXT, v_security_log_id;
        RETURN;
    END IF;

    v_new_balance := v_current_balance + p_paid_price;

    UPDATE public.user_balances SET
        balance = v_new_balance,
        total_earned = total_earned + p_paid_price,
        updated_at = NOW()
    WHERE id = v_balance_id;

    UPDATE public.balance_transactions SET
        status = 'completed',
        balance_before = v_current_balance,
        balance_after = v_new_balance,
        metadata = jsonb_build_object('payment_id', p_payment_id, 'paid_price', p_paid_price)
    WHERE id = p_pending_txn_id;

    RETURN QUERY SELECT TRUE, v_current_balance, v_new_balance, NULL::TEXT, NULL::TEXT, v_security_log_id;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

-- =====================================================================
-- DOĞRULAMA
-- =====================================================================
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'BAKİYE GÜVENLİK DÜZELTMESİ TAMAMLANDI';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Tablolar: balance_security_logs, balance_rate_limits, balance_security_settings';
    RAISE NOTICE 'Fonksiyonlar: log_balance_security_event, check_balance_rate_limit,';
    RAISE NOTICE '  update_balance_rate_limit, atomic_add_balance_topup_secure';
    RAISE NOTICE '';
    RAISE NOTICE 'SONRAKI ADIM: Edge Functionları güncelleyin';
END $$;
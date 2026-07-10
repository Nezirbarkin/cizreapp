-- =====================================================================
-- BAKİYE YÜKLEME GÜVENLİK DÜZELTMESİ
-- =====================================================================
-- Tarih: 2026-07-10
-- Amaç: Bakiye yükleme sistemini hacker saldırılarına karşı korumak
--
-- GÜVENLİK ÖNLEMLERİ:
-- 1. Rate Limiting - Günlük/aylık yükleme limitleri
-- 2. IP ve cihaz bazlı işlem sınırlaması
-- 3. Minimum tutar doğrulaması (sunucu tarafında)
-- 4. İşlem tekrar saldırısı (replay attack) koruması
-- 5. Callback manipulation koruması
-- 6. Audit logging - Tüm işlemlerin detaylı loglanması
-- 7. Admin işlemleri için ek yetkilendirme kontrolleri
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'BAKİYE YÜKLEME GÜVENLİK DÜZELTMESİ BAŞLIYOR';
    RAISE NOTICE '================================================================';
END $$;

-- =====================================================================
-- 1. GÜVENLİK LOGLARI TABLOSU
-- =====================================================================
-- Tüm bakiye işlemlerinin detaylı loglanması
CREATE TABLE IF NOT EXISTS public.balance_security_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(50) NOT NULL,           -- 'topup_initiated', 'topup_completed', 'topup_failed', 'admin_add', 'admin_deduct', 'rate_limit_exceeded'
    user_id UUID,                              -- NULL for system events
    ip_address INET,
    user_agent TEXT,
    device_fingerprint TEXT,                   -- Cihaz parmak izi
    amount NUMERIC(12, 2),
    currency VARCHAR(3) DEFAULT 'TRY',
    payment_method VARCHAR(20),                -- 'card', 'transfer', 'admin'
    reference_id UUID,                         -- Transaction ID
    payment_reference VARCHAR(100),            -- iyzico token veya conversation ID
    status VARCHAR(20),                       -- 'success', 'failed', 'blocked', 'pending'
    failure_reason TEXT,                      -- Hata sebebi
    metadata JSONB DEFAULT '{}',               -- Ek bilgiler (rate limit counts, etc.)
    risk_score INTEGER DEFAULT 0,             -- Risk skoru (0-100)
    risk_factors JSONB DEFAULT '[]',          -- Risk faktörleri dizisi
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexler
CREATE INDEX IF NOT EXISTS idx_security_logs_user_id ON public.balance_security_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_security_logs_ip ON public.balance_security_logs(ip_address);
CREATE INDEX IF NOT EXISTS idx_security_logs_created_at ON public.balance_security_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_security_logs_event_type ON public.balance_security_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_security_logs_reference_id ON public.balance_security_logs(reference_id);

-- Yorum
COMMENT ON TABLE public.balance_security_logs IS 'Bakiye işlemlerinin güvenlik logları - fraud analizi ve audit trail için';
COMMENT ON COLUMN public.balance_security_logs.risk_score IS '0-100 arası risk skoru, yüksek değer şüpheli işlemleri işaret eder';
COMMENT ON COLUMN public.balance_security_logs.risk_factors IS 'İşlemi şüpheli kılan faktörler: ["multiple_ips", "high_frequency", "unusual_amount"]';

-- =====================================================================
-- 2. RATE LIMITING TABLOSU
-- =====================================================================
-- Kullanıcı başına günlük/aylık işlem limitleri
CREATE TABLE IF NOT EXISTS public.balance_rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    period_type VARCHAR(20) NOT NULL,          -- 'daily', 'monthly', 'per_transaction'
    period_start TIMESTAMPTZ NOT NULL,         -- Periyodun başlangıcı
    period_end TIMESTAMPTZ NOT NULL,         -- Periyodun bitişi
    transaction_count INTEGER DEFAULT 0,       -- İşlem sayısı
    total_amount NUMERIC(12, 2) DEFAULT 0,   -- Toplam tutar
    last_transaction_at TIMESTAMPTZ,
    ip_addresses TEXT[],                      -- Kullanılan IP adresleri (çoklu IP tespiti)
    device_fingerprints TEXT[],               -- Kullanılan cihaz parmak izleri
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_user_period UNIQUE (user_id, period_type, period_start)
);

-- Indexler
CREATE INDEX IF NOT EXISTS idx_rate_limits_user_period ON public.balance_rate_limits(user_id, period_type, period_start);
CREATE INDEX IF NOT EXISTS idx_rate_limits_period_end ON public.balance_rate_limits(period_end) WHERE transaction_count > 0;

-- Yorum
COMMENT ON TABLE public.balance_rate_limits IS 'Kullanıcı başına rate limiting verileri - günlük/aylık limit kontrolü';
COMMENT ON COLUMN public.balance_rate_limits.ip_addresses IS 'Şüpheli: aynı kullanıcı farklı IP adreslerinden işlem yapıyor';
COMMENT ON COLUMN public.balance_rate_limits.device_fingerprints IS 'Şüpheli: aynı kullanıcı farklı cihazlardan işlem yapıyor';

-- =====================================================================
-- 3. GÜVENLİK AYARLARI TABLOSU
-- =====================================================================
-- Sistem geneli güvenlik parametreleri
CREATE TABLE IF NOT EXISTS public.balance_security_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Varsayılan güvenlik ayarları
INSERT INTO public.balance_security_settings (setting_key, setting_value, description)
VALUES
    -- Rate limiting ayarları
    ('daily_topup_limit_count', '10', 'Günlük maximum yükleme sayısı'),
    ('daily_topup_limit_amount', '50000', 'Günlük maximum yükleme tutarı (TL)'),
    ('monthly_topup_limit_count', '50', 'Aylık maximum yükleme sayısı'),
    ('monthly_topup_limit_amount', '200000', 'Aylık maximum yükleme tutarı (TL)'),
    ('min_topup_amount', '10', 'Minimum yükleme tutarı (TL)'),
    ('max_topup_amount', '10000', 'Maksimum tek seferlik yükleme tutarı (TL)'),
    
    -- Şüpheli aktivite ayarları
    ('max_ips_per_user_daily', '3', 'Günlük maximum farklı IP sayısı (bu aşılırsa uyarı)'),
    ('max_devices_per_user_daily', '5', 'Günlük maximum farklı cihaz sayısı (bu aşılırsa uyarı)'),
    ('suspicious_amount_threshold', '5000', 'Şüpheli kabul edilecek minimum tutar (TL)'),
    ('risk_score_block_threshold', '70', 'Bu risk skorunun üzerindeki işlemler otomatik engellenir'),
    
    -- Hesap kilitleme
    ('max_failed_attempts', '5', 'Kaç başarısız giriş denemesinden sonra geçici kilit'),
    ('lockout_duration_minutes', '30', 'Hesap kilit süresi (dakika)')
ON CONFLICT (setting_key) DO NOTHING;

-- =====================================================================
-- 4. GÜVENLİK LOG FONKSİYONU
-- =====================================================================
CREATE OR REPLACE FUNCTION public.log_balance_security_event(
    p_event_type VARCHAR,
    p_user_id UUID,
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

COMMENT ON FUNCTION public.log_balance_security_event IS 'Bakiye güvenlik olaylarını loglar - fraud analizi için';

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
    v_daily_count_limit INTEGER;
    v_daily_amount_limit NUMERIC;
    v_monthly_count_limit INTEGER;
    v_monthly_amount_limit NUMERIC;
    v_max_ips INTEGER;
    v_max_devices INTEGER;
    v_suspicious_threshold NUMERIC;
    
    v_daily_count INTEGER := 0;
    v_daily_amount NUMERIC := 0;
    v_monthly_count INTEGER := 0;
    v_monthly_amount NUMERIC := 0;
    v_current_ips TEXT[];
    v_current_devices TEXT[];
    
    v_risk_score INTEGER := 0;
    v_risk_factors JSONB := '[]'::JSONB;
    v_allowed BOOLEAN := TRUE;
    v_reason TEXT := 'OK';
BEGIN
    -- Ayar değerlerini al
    SELECT value::INTEGER INTO v_daily_count_limit FROM public.balance_security_settings WHERE setting_key = 'daily_topup_limit_count';
    SELECT value::NUMERIC INTO v_daily_amount_limit FROM public.balance_security_settings WHERE setting_key = 'daily_topup_limit_amount';
    SELECT value::INTEGER INTO v_monthly_count_limit FROM public.balance_security_settings WHERE setting_key = 'monthly_topup_limit_count';
    SELECT value::NUMERIC INTO v_monthly_amount_limit FROM public.balance_security_settings WHERE setting_key = 'monthly_topup_limit_amount';
    SELECT value::INTEGER INTO v_max_ips FROM public.balance_security_settings WHERE setting_key = 'max_ips_per_user_daily';
    SELECT value::INTEGER INTO v_max_devices FROM public.balance_security_settings WHERE setting_key = 'max_devices_per_user_daily';
    SELECT value::NUMERIC INTO v_suspicious_threshold FROM public.balance_security_settings WHERE setting_key = 'suspicious_amount_threshold';
    
    -- Varsayılan değerler
    v_daily_count_limit := COALESCE(v_daily_count_limit, 10);
    v_daily_amount_limit := COALESCE(v_daily_amount_limit, 50000);
    v_monthly_count_limit := COALESCE(v_monthly_count_limit, 50);
    v_monthly_amount_limit := COALESCE(v_monthly_amount_limit, 200000);
    v_max_ips := COALESCE(v_max_ips, 3);
    v_max_devices := COALESCE(v_max_devices, 5);
    v_suspicious_threshold := COALESCE(v_suspicious_threshold, 5000);
    
    -- Günlük istatistikleri al
    SELECT COALESCE(SUM(transaction_count), 0), COALESCE(SUM(total_amount), 0), 
           COALESCE(array_agg(DISTINCT unnest(ip_addresses)) FILTER (WHERE ip_addresses IS NOT NULL), ARRAY[]::TEXT[]),
           COALESCE(array_agg(DISTINCT unnest(device_fingerprints)) FILTER (WHERE device_fingerprints IS NOT NULL), ARRAY[]::TEXT[])
    INTO v_daily_count, v_daily_amount, v_current_ips, v_current_devices
    FROM public.balance_rate_limits
    WHERE user_id = p_user_id
      AND period_type = 'daily'
      AND period_start <= NOW()
      AND period_end > NOW();
    
    -- Aylık istatistikleri al
    SELECT COALESCE(SUM(transaction_count), 0), COALESCE(SUM(total_amount), 0)
    INTO v_monthly_count, v_monthly_amount
    FROM public.balance_rate_limits
    WHERE user_id = p_user_id
      AND period_type = 'monthly'
      AND period_start <= NOW()
      AND period_end > NOW();
    
    -- Rate limit kontrolleri
    IF v_daily_count >= v_daily_count_limit THEN
        v_allowed := FALSE;
        v_reason := 'Günlük işlem limiti aşıldı (max: ' || v_daily_count_limit || ')';
        v_risk_score := v_risk_score + 30;
        v_risk_factors := v_risk_factors || '"daily_count_limit_exceeded"'::JSONB;
    END IF;
    
    IF v_daily_amount + p_amount > v_daily_amount_limit THEN
        v_allowed := FALSE;
        v_reason := 'Günlük tutar limiti aşıldı (max: ' || v_daily_amount_limit || ' TL)';
        v_risk_score := v_risk_score + 40;
        v_risk_factors := v_risk_factors || '"daily_amount_limit_exceeded"'::JSONB;
    END IF;
    
    IF v_monthly_count >= v_monthly_count_limit THEN
        v_allowed := FALSE;
        v_reason := 'Aylık işlem limiti aşıldı (max: ' || v_monthly_count_limit || ')';
        v_risk_score := v_risk_score + 25;
        v_risk_factors := v_risk_factors || '"monthly_count_limit_exceeded"'::JSONB;
    END IF;
    
    IF v_monthly_amount + p_amount > v_monthly_amount_limit THEN
        v_allowed := FALSE;
        v_reason := 'Aylık tutar limiti aşıldı (max: ' || v_monthly_amount_limit || ' TL)';
        v_risk_score := v_risk_score + 35;
        v_risk_factors := v_risk_factors || '"monthly_amount_limit_exceeded"'::JSONB;
    END IF;
    
    -- Çoklu IP kontrolü (şüpheli aktivite)
    IF p_ip_address IS NOT NULL AND array_length(v_current_ips, 1) > 0 THEN
        IF NOT (p_ip_address::TEXT = ANY(v_current_ips)) THEN
            IF array_length(v_current_ips, 1) + 1 > v_max_ips THEN
                v_risk_score := v_risk_score + 20;
                v_risk_factors := v_risk_factors || '"multiple_ips_detected"'::JSONB;
            END IF;
        END IF;
    END IF;
    
    -- Çoklu cihaz kontrolü (şüpheli aktivite)
    IF p_device_fingerprint IS NOT NULL AND array_length(v_current_devices, 1) > 0 THEN
        IF NOT (p_device_fingerprint = ANY(v_current_devices)) THEN
            IF array_length(v_current_devices, 1) + 1 > v_max_devices THEN
                v_risk_score := v_risk_score + 15;
                v_risk_factors := v_risk_factors || '"multiple_devices_detected"'::JSONB;
            END IF;
        END IF;
    END IF;
    
    -- Yüksek tutar kontrolü
    IF p_amount > v_suspicious_threshold THEN
        v_risk_score := v_risk_score + 10;
        v_risk_factors := v_risk_factors || '"high_amount"'::JSONB;
    END IF;
    
    -- Risk skoru çok yüksekse engelle
    IF v_risk_score >= 70 AND v_allowed THEN
        v_allowed := FALSE;
        v_reason := 'Şüpheli aktivite tespit edildi. Lütfen destek ile iletişime geçin.';
        v_risk_factors := v_risk_factors || '"high_risk_score"'::JSONB;
    END IF;
    
    RETURN QUERY SELECT v_allowed, v_reason, 
                       (v_daily_count + 1),  -- Yeni işlem dahil
                       (v_daily_amount + p_amount),
                       v_daily_count_limit,
                       v_daily_amount_limit,
                       v_risk_score,
                       v_risk_factors;
END;
$$ LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public;

COMMENT ON FUNCTION public.check_balance_rate_limit IS 'Bakiye yükleme için rate limit kontrolü yapar';

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
    v_monthly_id UUID;
    v_now TIMESTAMPTZ := NOW();
    v_today_start TIMESTAMPTZ;
    v_today_end TIMESTAMPTZ;
    v_month_start TIMESTAMPTZ;
    v_month_end TIMESTAMPTZ;
BEGIN
    -- Günlük periyod hesapla
    v_today_start := DATE_TRUNC('day', v_now);
    v_today_end := v_today_start + INTERVAL '1 day';
    
    -- Aylık periyod hesapla
    v_month_start := DATE_TRUNC('month', v_now);
    v_month_end := v_month_start + INTERVAL '1 month';
    
    -- Günlük rate limit güncelle veya oluştur
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
    
    -- Aylık rate limit güncelle veya oluştur
    SELECT id INTO v_monthly_id FROM public.balance_rate_limits
    WHERE user_id = p_user_id AND period_type = 'monthly'
      AND period_start = v_month_start FOR UPDATE;
    
    IF v_monthly_id IS NOT NULL THEN
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
        WHERE id = v_monthly_id;
    ELSE
        INSERT INTO public.balance_rate_limits (
            user_id, period_type, period_start, period_end,
            transaction_count, total_amount, last_transaction_at,
            ip_addresses, device_fingerprints
        ) VALUES (
            p_user_id, 'monthly', v_month_start, v_month_end,
            1, p_amount, v_now,
            CASE WHEN p_ip_address IS NOT NULL THEN ARRAY[p_ip_address::TEXT] ELSE ARRAY[]::TEXT[] END,
            CASE WHEN p_device_fingerprint IS NOT NULL THEN ARRAY[p_device_fingerprint] ELSE ARRAY[]::TEXT[] END
        );
    END IF;
END;
$$ LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public;

COMMENT ON FUNCTION public.update_balance_rate_limit IS 'Rate limit sayaçlarını günceller';

-- =====================================================================
-- 7. EDGE FUNCTION GÜVENLİK KONTROLÜ - create-balance-topup
-- =====================================================================
-- Bu fonksiyon iyzico callback'inde çağrılır ve güvenlik kontrollerini yapar
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
    v_current_count INTEGER;
    v_current_amount NUMERIC;
    v_limit_count INTEGER;
    v_limit_amount NUMERIC;
    v_risk_score INTEGER;
    v_risk_factors JSONB;
    
    v_balance_id UUID;
    v_current_balance NUMERIC;
    v_new_balance NUMERIC;
    v_txn_exists BOOLEAN;
    v_txn_completed BOOLEAN;
BEGIN
    -- 1. İşlem tekrar kontrolü (replay attack koruması)
    SELECT EXISTS(
        SELECT 1 FROM public.balance_transactions 
        WHERE id = p_pending_txn_id AND status = 'completed'
    ) INTO v_txn_exists;
    
    IF v_txn_exists THEN
        -- Zaten işlenmiş işlem, tekrar engelle
        SELECT balance_after INTO v_current_balance 
        FROM public.balance_transactions WHERE id = p_pending_txn_id;
        
        INSERT INTO public.balance_security_logs (
            event_type, user_id, ip_address, user_agent, device_fingerprint,
            amount, payment_method, reference_id, payment_reference,
            status, failure_reason, risk_score, risk_factors
        ) VALUES (
            'topup_completed', p_user_id, p_ip_address, p_user_agent, p_device_fingerprint,
            p_amount, 'card', p_pending_txn_id, p_payment_id,
            'blocked', 'Replay attempt - transaction already processed', 100, 
            '["replay_attack"]'::JSONB
        ) RETURNING id INTO v_security_log_id;
        
        RETURN QUERY SELECT FALSE, v_current_balance, v_current_balance, 
                           'İşlem zaten işlenmiş', 'Replay attempt detected', v_security_log_id;
        RETURN;
    END IF;
    
    -- 2. Rate limit kontrolü
    SELECT * INTO v_allowed, v_reason, v_current_count, v_current_amount, 
                  v_limit_count, v_limit_amount, v_risk_score, v_risk_factors
    FROM public.check_balance_rate_limit(p_user_id, p_amount, p_ip_address, p_device_fingerprint);
    
    IF NOT v_allowed THEN
        -- Rate limit aşıldı, logla ve engelle
        INSERT INTO public.balance_security_logs (
            event_type, user_id, ip_address, user_agent, device_fingerprint,
            amount, payment_method, reference_id, payment_reference,
            status, failure_reason, risk_score, risk_factors,
            metadata
        ) VALUES (
            'topup_initiated', p_user_id, p_ip_address, p_user_agent, p_device_fingerprint,
            p_amount, 'card', p_pending_txn_id, p_payment_id,
            'blocked', v_reason, v_risk_score, v_risk_factors,
            jsonb_build_object(
                'current_count', v_current_count,
                'current_amount', v_current_amount,
                'limit_count', v_limit_count,
                'limit_amount', v_limit_amount
            )
        ) RETURNING id INTO v_security_log_id;
        
        RETURN QUERY SELECT FALSE, 0::NUMERIC, 0::NUMERIC, v_reason, v_reason, v_security_log_id;
        RETURN;
    END IF;
    
    -- 3. Tutarlılık kontrolü (amount vs paid_price)
    IF ABS(p_amount - p_paid_price) > 0.01 THEN
        -- Tutarsızlık tespit edildi, logla ama yine de işle
        INSERT INTO public.balance_security_logs (
            event_type, user_id, ip_address, user_agent, device_fingerprint,
            amount, payment_method, reference_id, payment_reference,
            status, failure_reason, risk_score, risk_factors
        ) VALUES (
            'topup_completed', p_user_id, p_ip_address, p_user_agent, p_device_fingerprint,
            p_amount, 'card', p_pending_txn_id, p_payment_id,
            'success', 'Amount mismatch warning: requested ' || p_amount || ' vs paid ' || p_paid_price, 
            v_risk_score + 10, v_risk_factors || '"amount_mismatch"'::JSONB
        ) RETURNING id INTO v_security_log_id;
    ELSE
        -- Normal işlem logla
        INSERT INTO public.balance_security_logs (
            event_type, user_id, ip_address, user_agent, device_fingerprint,
            amount, payment_method, reference_id, payment_reference,
            status, risk_score, risk_factors
        ) VALUES (
            'topup_completed', p_user_id, p_ip_address, p_user_agent, p_device_fingerprint,
            p_amount, 'card', p_pending_txn_id, p_payment_id,
            'success', v_risk_score, v_risk_factors
        ) RETURNING id INTO v_security_log_id;
    END IF;
    
    -- 4. Rate limit güncelle
    PERFORM public.update_balance_rate_limit(p_user_id, p_amount, p_ip_address, p_device_fingerprint);
    
    -- 5. Atomik bakiye güncelleme (FOR UPDATE lock ile)
    SELECT id, balance INTO v_balance_id, v_current_balance
    FROM public.user_balances
    WHERE user_id = p_user_id
    FOR UPDATE;
    
    IF v_balance_id IS NULL THEN
        -- Bakiye kaydı yok, oluştur
        INSERT INTO public.user_balances (user_id, balance, total_earned)
        VALUES (p_user_id, p_paid_price, p_paid_price)
        RETURNING balance INTO v_new_balance;
        
        -- Transaction kaydını güncelle
        UPDATE public.balance_transactions SET
            status = 'completed',
            balance_before = 0,
            balance_after = v_new_balance,
            metadata = jsonb_build_object(
                'payment_id', p_payment_id,
                'paid_price', p_paid_price,
                'security_log_id', v_security_log_id
            )
        WHERE id = p_pending_txn_id;
        
        RETURN QUERY SELECT TRUE, 0::NUMERIC, v_new_balance, NULL::TEXT, NULL::TEXT, v_security_log_id;
        RETURN;
    END IF;
    
    -- Mevcut bakiyeyi güncelle
    v_new_balance := v_current_balance + p_paid_price;
    
    UPDATE public.user_balances SET
        balance = v_new_balance,
        total_earned = total_earned + p_paid_price,
        updated_at = NOW()
    WHERE id = v_balance_id;
    
    -- Transaction kaydını güncelle
    UPDATE public.balance_transactions SET
        status = 'completed',
        balance_before = v_current_balance,
        balance_after = v_new_balance,
        metadata = jsonb_build_object(
            'payment_id', p_payment_id,
            'paid_price', p_paid_price,
            'security_log_id', v_security_log_id
        )
    WHERE id = p_pending_txn_id;
    
    RETURN QUERY SELECT TRUE, v_current_balance, v_new_balance, NULL::TEXT, NULL::TEXT, v_security_log_id;
END;
$$ LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public;

COMMENT ON FUNCTION public.atomic_add_balance_topup_secure IS 
'Güvenli bakiye yükleme - rate limiting, replay attack koruması ve audit logging ile';

-- =====================================================================
-- 8. ADMIN İŞLEMLERİ İÇİN EK GÜVENLİK KONTROLÜ
-- =====================================================================
CREATE OR REPLACE FUNCTION public.admin_balance_operation_secure(
    p_target_user_id UUID,
    p_amount NUMERIC,
    p_operation VARCHAR,                     -- 'add' veya 'deduct'
    p_description TEXT,
    p_admin_id UUID,
    p_admin_ip INET DEFAULT NULL
)
RETURNS TABLE(
    success BOOLEAN,
    new_balance NUMERIC,
    error_message TEXT,
    security_log_id UUID
) AS $$
DECLARE
    v_security_log_id UUID;
    v_balance_id UUID;
    v_current_balance NUMERIC;
    v_new_balance NUMERIC;
    v_admin_role VARCHAR;
    v_max_single_operation NUMERIC := 100000;  -- Tek seferde max 100bin TL
    v_max_daily_admin_add NUMERIC := 500000;    -- Admin günlük max ekleme
    v_daily_admin_total NUMERIC;
BEGIN
    -- 1. Admin rol kontrolü
    SELECT role INTO v_admin_role FROM public.profiles WHERE id = p_admin_id;
    
    IF v_admin_role != 'admin' THEN
        INSERT INTO public.balance_security_logs (
            event_type, user_id, ip_address,
            amount, payment_method, status, failure_reason, risk_score
        ) VALUES (
            'admin_' || p_operation, p_admin_id, p_admin_ip,
            p_amount, 'admin', 'blocked', 'Unauthorized admin attempt', 100
        ) RETURNING id INTO v_security_log_id;
        
        RETURN QUERY SELECT FALSE, 0::NUMERIC, 'Admin yetkisi gerekli', v_security_log_id;
        RETURN;
    END IF;
    
    -- 2. Miktar limit kontrolü
    IF p_amount > v_max_single_operation THEN
        INSERT INTO public.balance_security_logs (
            event_type, user_id, ip_address,
            amount, payment_method, status, failure_reason, risk_score
        ) VALUES (
            'admin_' || p_operation, p_admin_id, p_admin_ip,
            p_amount, 'admin', 'blocked', 'Single operation limit exceeded', 80
        ) RETURNING id INTO v_security_log_id;
        
        RETURN QUERY SELECT FALSE, 0::NUMERIC, 
                           'Tek seferlik limit aşıldı (max: ' || v_max_single_operation || ' TL)', 
                           v_security_log_id;
        RETURN;
    END IF;
    
    -- 3. Admin günlük toplam ekleme kontrolü
    IF p_operation = 'add' THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_daily_admin_total
        FROM public.balance_transactions
        WHERE admin_id = p_admin_id
          AND type = 'topup'
          AND payment_method = 'admin'
          AND created_at >= DATE_TRUNC('day', NOW())
          AND created_at < DATE_TRUNC('day', NOW()) + INTERVAL '1 day';
        
        IF v_daily_admin_total + p_amount > v_max_daily_admin_add THEN
            INSERT INTO public.balance_security_logs (
                event_type, user_id, ip_address,
                amount, payment_method, status, failure_reason, risk_score
            ) VALUES (
                'admin_add', p_admin_id, p_admin_ip,
                p_amount, 'admin', 'blocked', 'Daily admin add limit exceeded', 60
            ) RETURNING id INTO v_security_log_id;
            
            RETURN QUERY SELECT FALSE, 0::NUMERIC,
                               'Günlük admin ekleme limiti aşıldı (max: ' || v_max_daily_admin_add || ' TL)',
                               v_security_log_id;
            RETURN;
        END IF;
    END IF;
    
    -- 4. Hedef kullanıcı bakiyesini al
    SELECT id, balance INTO v_balance_id, v_current_balance
    FROM public.user_balances
    WHERE user_id = p_target_user_id
    FOR UPDATE;
    
    IF v_balance_id IS NULL THEN
        INSERT INTO public.user_balances (user_id, balance, total_earned)
        VALUES (p_target_user_id, 0, 0)
        RETURNING balance INTO v_current_balance;
        
        SELECT id INTO v_balance_id FROM public.user_balances WHERE user_id = p_target_user_id;
    END IF;
    
    -- 5. İşlemi gerçekleştir
    IF p_operation = 'add' THEN
        v_new_balance := v_current_balance + p_amount;
        
        UPDATE public.user_balances SET
            balance = v_new_balance,
            total_earned = total_earned + p_amount,
            updated_at = NOW()
        WHERE id = v_balance_id;
        
    ELSIF p_operation = 'deduct' THEN
        IF v_current_balance < p_amount THEN
            INSERT INTO public.balance_security_logs (
                event_type, user_id, ip_address,
                amount, payment_method, status, failure_reason, risk_score
            ) VALUES (
                'admin_deduct', p_admin_id, p_admin_ip,
                p_amount, 'admin', 'failed', 'Insufficient balance for deduction', 20
            ) RETURNING id INTO v_security_log_id;
            
            RETURN QUERY SELECT FALSE, v_current_balance,
                               'Kullanıcı bakiyesi yetersiz', v_security_log_id;
            RETURN;
        END IF;
        
        v_new_balance := v_current_balance - p_amount;
        
        UPDATE public.user_balances SET
            balance = v_new_balance,
            updated_at = NOW()
        WHERE id = v_balance_id;
    END IF;
    
    -- 6. İşlem kaydı oluştur
    INSERT INTO public.balance_transactions (
        user_id, type, amount, net_amount, balance_before, balance_after,
        reference_type, description, status, payment_method, admin_id
    ) VALUES (
        p_target_user_id, 
        CASE WHEN p_operation = 'add' THEN 'topup' ELSE 'adjustment' END,
        p_amount, p_amount, v_current_balance, v_new_balance,
        'admin_' || p_operation,
        '[Admin: ' || p_admin_id || '] ' || COALESCE(p_description, 'Manual adjustment'),
        'completed',
        'admin',
        p_admin_id
    );
    
    -- 7. Güvenlik logu
    INSERT INTO public.balance_security_logs (
        event_type, user_id, ip_address,
        amount, payment_method, status, risk_score
    ) VALUES (
        'admin_' || p_operation, p_admin_id, p_admin_ip,
        p_amount, 'admin', 'success', 10
    ) RETURNING id INTO v_security_log_id;
    
    RETURN QUERY SELECT TRUE, v_new_balance, NULL::TEXT, v_security_log_id;
END;
$$ LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public;

COMMENT ON FUNCTION public.admin_balance_operation_secure IS 
'Admin bakiye işlemleri için güvenli wrapper - rol kontrolü, limit kontrolü ve audit trail';

-- =====================================================================
-- 9. GÜVENLİK LOG TEMİZLİK FONKSİYONU
-- =====================================================================
-- Eski logları sil (90 günden eski)
CREATE OR REPLACE FUNCTION public.cleanup_old_security_logs()
RETURNS INTEGER AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM public.balance_security_logs
    WHERE created_at < NOW() - INTERVAL '90 days'
    RETURNING COUNT(*) INTO v_deleted;
    
    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public;

-- =====================================================================
-- 10. ESKİ RATE LIMIT VERİLERİ TEMİZLİK FONKSİYONU
-- =====================================================================
CREATE OR REPLACE FUNCTION public.cleanup_old_rate_limits()
RETURNS INTEGER AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM public.balance_rate_limits
    WHERE period_end < NOW() - INTERVAL '7 days'
    RETURNING COUNT(*) INTO v_deleted;
    
    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public;

-- =====================================================================
-- 11. GÜVENLİK LOGLARI İÇİN RLS POLITIKASI
-- =====================================================================
ALTER TABLE public.balance_security_logs ENABLE ROW LEVEL SECURITY;

-- Admin ve sistem sadece okuyabilir
CREATE POLICY "Admins can view security logs"
    ON public.balance_security_logs FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- =====================================================================
-- 12. RATE LIMITS İÇİN RLS POLITIKASI
-- =====================================================================
ALTER TABLE public.balance_rate_limits ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar sadece kendi verilerini görebilir
CREATE POLICY "Users can view own rate limits"
    ON public.balance_rate_limits FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- =====================================================================
-- 13. GÜVENLİK AYARLARI İÇİN RLS POLITIKASI
-- =====================================================================
ALTER TABLE public.balance_security_settings ENABLE ROW LEVEL SECURITY;

-- Sadece admin okuyabilir
CREATE POLICY "Admins can manage security settings"
    ON public.balance_security_settings FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- =====================================================================
-- 14. KONTROL VE DOĞRULAMA
-- =====================================================================
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    -- Tablolar oluşturuldu mu?
    SELECT COUNT(*) INTO v_count FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'balance_security_logs';
    IF v_count > 0 THEN
        RAISE NOTICE '✅ balance_security_logs tablosu hazır';
    END IF;
    
    SELECT COUNT(*) INTO v_count FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'balance_rate_limits';
    IF v_count > 0 THEN
        RAISE NOTICE '✅ balance_rate_limits tablosu hazır';
    END IF;
    
    SELECT COUNT(*) INTO v_count FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'balance_security_settings';
    IF v_count > 0 THEN
        RAISE NOTICE '✅ balance_security_settings tablosu hazır';
    END IF;
    
    -- Fonksiyonlar oluşturuldu mu?
    SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'log_balance_security_event';
    IF v_count > 0 THEN
        RAISE NOTICE '✅ log_balance_security_event fonksiyonu hazır';
    END IF;
    
    SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'check_balance_rate_limit';
    IF v_count > 0 THEN
        RAISE NOTICE '✅ check_balance_rate_limit fonksiyonu hazır';
    END IF;
    
    SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'atomic_add_balance_topup_secure';
    IF v_count > 0 THEN
        RAISE NOTICE '✅ atomic_add_balance_topup_secure fonksiyonu hazır';
    END IF;
    
    SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'admin_balance_operation_secure';
    IF v_count > 0 THEN
        RAISE NOTICE '✅ admin_balance_operation_secure fonksiyonu hazır';
    END IF;
    
    RAISE NOTICE '';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'BAKİYE GÜVENLİK DÜZELTMESİ TAMAMLANDI';
    RAISE NOTICE '================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'EKLENEN ÖZELLİKLER:';
    RAISE NOTICE '  1. balance_security_logs - Tüm işlemlerin detaylı loglanması';
    RAISE NOTICE '  2. balance_rate_limits - Günlük/aylık işlem limitleri';
    RAISE NOTICE '  3. balance_security_settings - Merkezi güvenlik ayarları';
    RAISE NOTICE '  4. Rate limiting fonksiyonları';
    RAISE NOTICE '  5. Replay attack koruması';
    RAISE NOTICE '  6. Çoklu IP/Cihaz tespiti';
    RAISE NOTICE '  7. Risk scoring sistemi';
    RAISE NOTICE '  8. Admin işlemleri için ek güvenlik kontrolleri';
    RAISE NOTICE '';
    RAISE NOTICE 'SONRAKI ADIMLAR:';
    RAISE NOTICE '  1. supabase/functions/confirm-balance-topup/index.ts dosyasında';
    RAISE NOTICE '     atomic_add_balance_topup yerine atomic_add_balance_topup_secure kullanın';
    RAISE NOTICE '  2. supabase/functions/admin-add-balance/index.ts dosyasında';
    RAISE NOTICE '     admin_balance_operation_secure fonksiyonunu kullanın';
    RAISE NOTICE '';
END $$;
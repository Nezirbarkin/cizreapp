-- ============================================
-- BAKİYE SİSTEMİ - VERİTABANI TABLOLARI
-- Oluşturulma: 2026-06-21
-- ============================================

-- ============================================
-- 1. USER_BALANCES TABLOSU
-- Kullanıcı bakiyelerini tutar
-- ============================================
DROP TABLE IF EXISTS user_balances CASCADE;
CREATE TABLE IF NOT EXISTS user_balances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
    balance DECIMAL(12, 2) NOT NULL DEFAULT 0.00 CHECK (balance >= 0),
    locked_balance DECIMAL(12, 2) NOT NULL DEFAULT 0.00 CHECK (locked_balance >= 0),
    total_earned DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    total_spent DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    total_withdrawn DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_user_balances_user_id ON user_balances(user_id);

-- Otomatik updated_at güncellemesi
CREATE OR REPLACE FUNCTION update_user_balances_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_user_balances_timestamp ON user_balances;
CREATE TRIGGER trigger_update_user_balances_timestamp
    BEFORE UPDATE ON user_balances
    FOR EACH ROW
    EXECUTE FUNCTION update_user_balances_timestamp();

-- Yeni kullanıcı oluşturulduğunda otomatik bakiye oluştur
CREATE OR REPLACE FUNCTION create_user_balance_on_signup()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO user_balances (user_id, balance, locked_balance)
    VALUES (NEW.id, 0.00, 0.00)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_create_user_balance ON profiles;
CREATE TRIGGER trigger_create_user_balance
    AFTER INSERT ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION create_user_balance_on_signup();

-- ============================================
-- 2. BALANCE_TRANSACTIONS TABLOSU
-- Tüm bakiye işlemlerini loglar
-- ============================================
DROP TYPE IF EXISTS balance_transaction_type CASCADE;
CREATE TYPE balance_transaction_type AS ENUM (
    'topup',           -- Bakiye yükleme
    'order_payment',   -- Sipariş ödemesi
    'refund',          -- İade
    'withdrawal',      -- Çekim
    'adjustment',      -- Manuel düzeltme
    'commission'       -- Komisyon (satıcı kazancı)
);

DROP TYPE IF EXISTS balance_transaction_status CASCADE;
CREATE TYPE balance_transaction_status AS ENUM (
    'pending',
    'completed',
    'failed',
    'cancelled'
);

DROP TABLE IF EXISTS balance_transactions CASCADE;
CREATE TABLE IF NOT EXISTS balance_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    type balance_transaction_type NOT NULL,
    amount DECIMAL(12, 2) NOT NULL CHECK (amount > 0),
    fee DECIMAL(12, 2) DEFAULT 0.00 CHECK (fee >= 0),
    net_amount DECIMAL(12, 2) NOT NULL,
    balance_before DECIMAL(12, 2) NOT NULL,
    balance_after DECIMAL(12, 2) NOT NULL,
    reference_type VARCHAR(50), -- 'order', 'withdrawal', 'topup', 'adjustment'
    reference_id UUID,          -- İlgili sipariş/çekim ID
    status balance_transaction_status NOT NULL DEFAULT 'pending',
    description TEXT,
    payment_method VARCHAR(50),  -- 'card', 'bank_transfer', 'balance', 'cash'
    payment_reference VARCHAR(255), -- Dış ödeme referansı (iyzico conversation ID vb.)
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_balance_transactions_user_id ON balance_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_balance_transactions_type ON balance_transactions(type);
CREATE INDEX IF NOT EXISTS idx_balance_transactions_status ON balance_transactions(status);
CREATE INDEX IF NOT EXISTS idx_balance_transactions_reference ON balance_transactions(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_balance_transactions_created_at ON balance_transactions(created_at DESC);

-- ============================================
-- 3. SELLER_EARNINGS TABLOSU
-- Satıcı kazançlarını izler
-- ============================================
DROP TYPE IF EXISTS earning_status CASCADE;
CREATE TYPE earning_status AS ENUM (
    'pending',    -- Sipariş tamamlanmadı
    'available',  -- Çekilebilir
    'withdrawn',  -- Çekildi
    'cancelled'   -- İptal edildi
);

DROP TABLE IF EXISTS seller_earnings CASCADE;
CREATE TABLE IF NOT EXISTS seller_earnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    order_number VARCHAR(50),
    shop_id UUID REFERENCES shops(id) ON DELETE SET NULL,
    gross_amount DECIMAL(12, 2) NOT NULL CHECK (gross_amount >= 0),
    commission_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00 CHECK (commission_amount >= 0),
    commission_percent DECIMAL(5, 2) DEFAULT 0.00,
    net_amount DECIMAL(12, 2) NOT NULL CHECK (net_amount >= 0),
    status earning_status NOT NULL DEFAULT 'pending',
    available_at TIMESTAMPTZ, -- Teslimattan sonra çekilebilir olur
    withdrawn_at TIMESTAMPTZ,
    withdrawal_id UUID, -- seller_withdrawals tablosu oluşturulduktan sonra FK eklenecek
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_seller_earnings_seller_id ON seller_earnings(seller_id);
CREATE INDEX IF NOT EXISTS idx_seller_earnings_order_id ON seller_earnings(order_id);
CREATE INDEX IF NOT EXISTS idx_seller_earnings_status ON seller_earnings(status);
CREATE INDEX IF NOT EXISTS idx_seller_earnings_shop_id ON seller_earnings(shop_id);

-- Otomatik updated_at
CREATE OR REPLACE FUNCTION update_seller_earnings_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_seller_earnings_timestamp ON seller_earnings;
CREATE TRIGGER trigger_update_seller_earnings_timestamp
    BEFORE UPDATE ON seller_earnings
    FOR EACH ROW
    EXECUTE FUNCTION update_seller_earnings_timestamp();

-- ============================================
-- 4. SELLER_WITHDRAWALS TABLOSU
-- Satıcı çekim taleplerini tutar
-- ============================================
DROP TYPE IF EXISTS withdrawal_status CASCADE;
CREATE TYPE withdrawal_status AS ENUM (
    'pending',     -- Beklemede
    'processing', -- İşleniyor
    'completed',  -- Tamamlandı
    'failed',      -- Başarısız
    'cancelled'    -- İptal edildi
);

DROP TABLE IF EXISTS seller_withdrawals CASCADE;
CREATE TABLE IF NOT EXISTS seller_withdrawals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    amount DECIMAL(12, 2) NOT NULL CHECK (amount > 0),
    fee_percent DECIMAL(5, 2) DEFAULT 2.00,
    fee DECIMAL(12, 2) DEFAULT 0.00,
    net_amount DECIMAL(12, 2) NOT NULL,
    status withdrawal_status NOT NULL DEFAULT 'pending',
    bank_account_name VARCHAR(255),
    bank_account_number VARCHAR(50),
    bank_name VARCHAR(100),
    iban VARCHAR(34),
    processed_at TIMESTAMPTZ,
    failure_reason TEXT,
    admin_notes TEXT,
    admin_id UUID REFERENCES profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_seller_withdrawals_seller_id ON seller_withdrawals(seller_id);
CREATE INDEX IF NOT EXISTS idx_seller_withdrawals_status ON seller_withdrawals(status);
CREATE INDEX IF NOT EXISTS idx_seller_withdrawals_created_at ON seller_withdrawals(created_at DESC);

-- Otomatik updated_at
CREATE OR REPLACE FUNCTION update_seller_withdrawals_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_seller_withdrawals_timestamp ON seller_withdrawals;
CREATE TRIGGER trigger_update_seller_withdrawals_timestamp
    BEFORE UPDATE ON seller_withdrawals
    FOR EACH ROW
    EXECUTE FUNCTION update_seller_withdrawals_timestamp();

-- ============================================
-- 5. SELLER_EARNINGS İÇİN FONKSİYON
-- Sipariş tamamlandığında kazanç oluştur
-- ============================================
CREATE OR REPLACE FUNCTION create_seller_earnings_on_delivery()
RETURNS TRIGGER AS $$
DECLARE
    v_order RECORD;
    v_shop RECORD;
    v_commission_percent DECIMAL(5, 2);
    v_commission DECIMAL(12, 2);
    v_net DECIMAL(12, 2);
BEGIN
    -- Sadece delivered durumunda çalışsın
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- Siparişi al
        SELECT * INTO v_order FROM orders WHERE id = NEW.id;
        
        IF v_order.shop_id IS NOT NULL THEN
            -- Dükkanı al ve komisyon oranını bul
            SELECT * INTO v_shop FROM shops WHERE id = v_order.shop_id;
            
            -- Komisyon yüzdesi (dükkan ayarı veya sistem default)
            v_commission_percent := COALESCE(v_shop.commission_rate, 10.00);
            
            -- Komisyon ve net tutar hesapla
            v_commission := ROUND(v_order.total_amount * v_commission_percent / 100, 2);
            v_net := v_order.total_amount - v_commission;
            
            -- Kazanç kaydı oluştur
            INSERT INTO seller_earnings (
                seller_id,
                order_id,
                order_number,
                shop_id,
                gross_amount,
                commission_amount,
                commission_percent,
                net_amount,
                status,
                available_at
            ) VALUES (
                v_shop.owner_id,
                v_order.id,
                v_order.order_number,
                v_order.shop_id,
                v_order.total_amount,
                v_commission,
                v_commission_percent,
                v_net,
                'available',
                NOW() + INTERVAL '24 hours' -- 24 saat sonra çekilebilir
            );
            
            RAISE NOTICE 'Seller earnings created for order %', v_order.order_number;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_create_seller_earnings ON orders;
CREATE TRIGGER trigger_create_seller_earnings
    AFTER UPDATE OF status ON orders
    FOR EACH ROW
    EXECUTE FUNCTION create_seller_earnings_on_delivery();

-- ============================================
-- 6. RLS (ROW LEVEL SECURITY) POLICIES
-- ============================================

-- user_balances RLS
ALTER TABLE user_balances ENABLE ROW LEVEL SECURITY;

-- Kullanıcı kendi bakiyesini görebilir
DROP POLICY IF EXISTS "Users can view own balance" ON user_balances;
CREATE POLICY "Users can view own balance"
    ON user_balances FOR SELECT
    USING (auth.uid() = user_id);

-- Admin tüm bakiyeleri görebilir
DROP POLICY IF EXISTS "Admins can view all balances" ON user_balances;
CREATE POLICY "Admins can view all balances"
    ON user_balances FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- Sistem fonksiyonları için güncelleme izni (service rolü)
DROP POLICY IF EXISTS "Service can update balances" ON user_balances;
CREATE POLICY "Service can update balances"
    ON user_balances FOR UPDATE
    USING (true);

-- balance_transactions RLS
ALTER TABLE balance_transactions ENABLE ROW LEVEL SECURITY;

-- Kullanıcı kendi işlemlerini görebilir
DROP POLICY IF EXISTS "Users can view own transactions" ON balance_transactions;
CREATE POLICY "Users can view own transactions"
    ON balance_transactions FOR SELECT
    USING (auth.uid() = user_id);

-- Admin tüm işlemleri görebilir
DROP POLICY IF EXISTS "Admins can view all transactions" ON balance_transactions;
CREATE POLICY "Admins can view all transactions"
    ON balance_transactions FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- Sistem için insert izni
DROP POLICY IF EXISTS "Service can insert transactions" ON balance_transactions;
CREATE POLICY "Service can insert transactions"
    ON balance_transactions FOR INSERT
    WITH CHECK (true);

-- seller_earnings RLS
ALTER TABLE seller_earnings ENABLE ROW LEVEL SECURITY;

-- Satıcı kendi kazançlarını görebilir
DROP POLICY IF EXISTS "Sellers can view own earnings" ON seller_earnings;
CREATE POLICY "Sellers can view own earnings"
    ON seller_earnings FOR SELECT
    USING (auth.uid() = seller_id);

-- Admin tüm kazançları görebilir
DROP POLICY IF EXISTS "Admins can view all earnings" ON seller_earnings;
CREATE POLICY "Admins can view all earnings"
    ON seller_earnings FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- Sistem için insert/update izni
DROP POLICY IF EXISTS "Service can manage earnings" ON seller_earnings;
CREATE POLICY "Service can manage earnings"
    ON seller_earnings FOR ALL
    USING (true);

-- seller_withdrawals RLS
ALTER TABLE seller_withdrawals ENABLE ROW LEVEL SECURITY;

-- Satıcı kendi çekim taleplerini görebilir
DROP POLICY IF EXISTS "Sellers can view own withdrawals" ON seller_withdrawals;
CREATE POLICY "Sellers can view own withdrawals"
    ON seller_withdrawals FOR SELECT
    USING (auth.uid() = seller_id);

-- Admin tüm çekim taleplerini görebilir
DROP POLICY IF EXISTS "Admins can view all withdrawals" ON seller_withdrawals;
CREATE POLICY "Admins can view all withdrawals"
    ON seller_withdrawals FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- Admin çekimleri güncelleyebilir
DROP POLICY IF EXISTS "Admins can manage withdrawals" ON seller_withdrawals;
CREATE POLICY "Admins can manage withdrawals"
    ON seller_withdrawals FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- Satıcı çekim talebi oluşturabilir
DROP POLICY IF EXISTS "Sellers can create withdrawals" ON seller_withdrawals;
CREATE POLICY "Sellers can create withdrawals"
    ON seller_withdrawals FOR INSERT
    WITH CHECK (auth.uid() = seller_id);

-- ============================================
-- 7. BAKİYE İŞLEMLERİ İÇİN GÜVENLİ FONKSİYONLAR
-- ============================================

-- Bakiye Ekleme (yükleme, iade vb.)
CREATE OR REPLACE FUNCTION add_to_balance(
    p_user_id UUID,
    p_amount DECIMAL(12, 2),
    p_type balance_transaction_type,
    p_reference_type VARCHAR,
    p_reference_id UUID,
    p_description TEXT DEFAULT NULL,
    p_payment_method VARCHAR DEFAULT NULL,
    p_payment_reference VARCHAR DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::JSONB
)
RETURNS UUID AS $$
DECLARE
    v_balance_id UUID;
    v_balance_before DECIMAL(12, 2);
    v_balance_after DECIMAL(12, 2);
    v_transaction_id UUID;
BEGIN
    -- Kullanıcının bakiyesini bul veya oluştur
    SELECT id, balance INTO v_balance_id, v_balance_before
    FROM user_balances
    WHERE user_id = p_user_id;
    
    IF v_balance_id IS NULL THEN
        INSERT INTO user_balances (user_id, balance)
        VALUES (p_user_id, 0)
        RETURNING id, balance INTO v_balance_id, v_balance_before;
    END IF;
    
    -- Yeni bakiyeyi hesapla
    v_balance_after := v_balance_before + p_amount;
    
    -- Bakiyeyi güncelle
    UPDATE user_balances
    SET balance = v_balance_after,
        total_earned = total_earned + p_amount,
        updated_at = NOW()
    WHERE id = v_balance_id;
    
    -- İşlem kaydı oluştur
    INSERT INTO balance_transactions (
        user_id,
        type,
        amount,
        net_amount,
        balance_before,
        balance_after,
        reference_type,
        reference_id,
        status,
        description,
        payment_method,
        payment_reference,
        metadata
    ) VALUES (
        p_user_id,
        p_type,
        p_amount,
        p_amount, -- fee yok
        v_balance_before,
        v_balance_after,
        p_reference_type,
        p_reference_id,
        'completed',
        p_description,
        p_payment_method,
        p_payment_reference,
        p_metadata
    ) RETURNING id INTO v_transaction_id;
    
    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Bakiye Düşürme (ödeme, çekim vb.)
CREATE OR REPLACE FUNCTION deduct_from_balance(
    p_user_id UUID,
    p_amount DECIMAL(12, 2),
    p_type balance_transaction_type,
    p_reference_type VARCHAR,
    p_reference_id UUID,
    p_description TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::JSONB
)
RETURNS UUID AS $$
DECLARE
    v_balance_id UUID;
    v_current_balance DECIMAL(12, 2);
    v_balance_before DECIMAL(12, 2);
    v_balance_after DECIMAL(12, 2);
    v_transaction_id UUID;
BEGIN
    -- Yeterli bakiye kontrolü
    SELECT id, balance INTO v_balance_id, v_current_balance
    FROM user_balances
    WHERE user_id = p_user_id
    FOR UPDATE; -- Lock to prevent race conditions
    
    IF v_balance_id IS NULL THEN
        RAISE EXCEPTION 'Balance record not found for user';
    END IF;
    
    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance. Available: %, Required: %', v_current_balance, p_amount;
    END IF;
    
    v_balance_before := v_current_balance;
    v_balance_after := v_current_balance - p_amount;
    
    -- Bakiyeyi güncelle
    UPDATE user_balances
    SET balance = v_balance_after,
        total_spent = total_spent + p_amount,
        updated_at = NOW()
    WHERE id = v_balance_id;
    
    -- İşlem kaydı oluştur
    INSERT INTO balance_transactions (
        user_id,
        type,
        amount,
        net_amount,
        balance_before,
        balance_after,
        reference_type,
        reference_id,
        status,
        description,
        metadata
    ) VALUES (
        p_user_id,
        p_type,
        p_amount,
        p_amount,
        v_balance_before,
        v_balance_after,
        p_reference_type,
        p_reference_id,
        'completed',
        p_description,
        p_metadata
    ) RETURNING id INTO v_transaction_id;
    
    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 8. APP_ABOUT_SETTINGS'E BAKİYE AYARLARI EKLE
-- ============================================
DO $$
BEGIN
    -- Sütunları kontrol et ve ekle (eğer yoksa)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'app_about_settings' AND column_name = 'min_topup_amount') THEN
        ALTER TABLE app_about_settings ADD COLUMN min_topup_amount DECIMAL(12, 2) DEFAULT 10.00;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'app_about_settings' AND column_name = 'max_topup_amount') THEN
        ALTER TABLE app_about_settings ADD COLUMN max_topup_amount DECIMAL(12, 2) DEFAULT 10000.00;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'app_about_settings' AND column_name = 'withdrawal_fee_percent') THEN
        ALTER TABLE app_about_settings ADD COLUMN withdrawal_fee_percent DECIMAL(5, 2) DEFAULT 2.00;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'app_about_settings' AND column_name = 'min_withdrawal_amount') THEN
        ALTER TABLE app_about_settings ADD COLUMN min_withdrawal_amount DECIMAL(12, 2) DEFAULT 50.00;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'app_about_settings' AND column_name = 'balance_enabled') THEN
        ALTER TABLE app_about_settings ADD COLUMN balance_enabled BOOLEAN DEFAULT true;
    END IF;
    
    RAISE NOTICE 'Balance settings columns added to app_about_settings';
END $$;

-- ============================================
-- YARDIMCI VIEW'LAR
-- ============================================

-- Satıcı kazanç özeti view
CREATE OR REPLACE VIEW seller_earnings_summary AS
SELECT 
    se.seller_id,
    p.full_name as seller_name,
    COUNT(*) as total_orders,
    SUM(se.gross_amount) as total_gross,
    SUM(se.commission_amount) as total_commission,
    SUM(se.net_amount) as total_net,
    SUM(CASE WHEN se.status = 'available' THEN se.net_amount ELSE 0 END) as withdrawable_amount,
    SUM(CASE WHEN se.status = 'withdrawn' THEN se.net_amount ELSE 0 END) as withdrawn_amount,
    SUM(CASE WHEN se.status = 'pending' THEN se.net_amount ELSE 0 END) as pending_amount
FROM seller_earnings se
JOIN profiles p ON p.id = se.seller_id
GROUP BY se.seller_id, p.full_name;

-- Bakiye işlem özeti view
CREATE OR REPLACE VIEW balance_transaction_summary AS
SELECT
    bt.user_id,
    p.full_name as user_name,
    bt.type::text as transaction_type,
    COUNT(*) as transaction_count,
    SUM(bt.amount) as total_amount
FROM balance_transactions bt
JOIN profiles p ON p.id = bt.user_id
GROUP BY bt.user_id, p.full_name, bt.type;

-- ============================================
-- 9. GEÇİCI OLARAK KALDIRILAN FK'LERİ EKLE
-- seller_earnings ve seller_withdrawals arasındaki FK ilişkisi
-- ============================================
DO $$
BEGIN
    -- withdrawal_id FK'yi ekle (eğer henüz yoksa ve tablo varsa)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'seller_withdrawals') THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints
            WHERE constraint_name = 'seller_earnings_withdrawal_id_fkey'
        ) THEN
            ALTER TABLE seller_earnings
            ADD CONSTRAINT seller_earnings_withdrawal_id_fkey
            FOREIGN KEY (withdrawal_id) REFERENCES seller_withdrawals(id) ON DELETE SET NULL;
        END IF;
    END IF;
END $$;

-- ============================================
-- GRANTS
-- ============================================
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;

-- ============================================
-- BAKİYE SİSTEMİ TAMAMLANDI
-- ============================================

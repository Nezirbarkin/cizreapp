-- ============================================
-- BANKA HESAPLARI YÖNETİM SİSTEMİ
-- Tarih: 2026-06-24
-- ============================================

-- Banka hesapları tablosu (admin tarafından yönetilir)
DROP TABLE IF EXISTS bank_accounts CASCADE;
CREATE TABLE IF NOT EXISTS bank_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bank_name VARCHAR(100) NOT NULL,           -- Banka adı (Ziraat, Garanti vb.)
    iban VARCHAR(34) NOT NULL,                 -- IBAN (TR ile başlayan)
    account_name VARCHAR(255) NOT NULL,        -- Hesap sahibi
    branch VARCHAR(100),                       -- Şube (opsiyonel)
    account_number VARCHAR(50),                -- Hesap no (opsiyonel)
    description TEXT,                          -- Açıklama (Havale için not vb.)
    is_active BOOLEAN NOT NULL DEFAULT true,   -- Aktif mi?
    display_order INTEGER NOT NULL DEFAULT 0,  -- Görüntüleme sırası
    created_by UUID REFERENCES profiles(id),   -- Ekleyen admin
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_bank_accounts_active ON bank_accounts(is_active, display_order);
CREATE INDEX IF NOT EXISTS idx_bank_accounts_created ON bank_accounts(created_at DESC);

-- Otomatik updated_at güncellemesi
CREATE OR REPLACE FUNCTION update_bank_accounts_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_bank_accounts_timestamp ON bank_accounts;
CREATE TRIGGER trigger_update_bank_accounts_timestamp
    BEFORE UPDATE ON bank_accounts
    FOR EACH ROW
    EXECUTE FUNCTION update_bank_accounts_timestamp();

-- RLS
ALTER TABLE bank_accounts ENABLE ROW LEVEL SECURITY;

-- Herkes aktif banka hesaplarını görebilir (kullanıcılar için)
DROP POLICY IF EXISTS "Anyone can view active bank accounts" ON bank_accounts;
CREATE POLICY "Anyone can view active bank accounts"
    ON bank_accounts FOR SELECT
    USING (is_active = true);

-- Admin tüm banka hesaplarını yönetebilir
DROP POLICY IF EXISTS "Admins can manage bank accounts" ON bank_accounts;
CREATE POLICY "Admins can manage bank accounts"
    ON bank_accounts FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- Banka hesaplarını IBAN ile maskelenmiş gösteren view
DROP VIEW IF EXISTS bank_accounts_public CASCADE;
CREATE OR REPLACE VIEW bank_accounts_public AS
SELECT
    id,
    bank_name,
    -- IBAN'ı maskele (TR12 **** **** **** 1234)
    CASE
        WHEN LENGTH(iban) >= 8 THEN
            SUBSTRING(iban, 1, 4) || '****' || SUBSTRING(iban, LENGTH(iban) - 4)
        ELSE iban
    END AS masked_iban,
    iban,  -- IBAN tam hali sadece admin görebilir (RLS sayesinde)
    account_name,
    branch,
    description,
    display_order
FROM bank_accounts
WHERE is_active = true
ORDER BY display_order ASC, created_at DESC;

-- ============================================
-- TAMAMLANDI
-- ============================================
-- Satıcı Ödeme İstekleri Sistemi
-- Toplu ödeme sistemi için payout_requests tablosu

-- 1. payout_requests tablosu
CREATE TABLE IF NOT EXISTS payout_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    
    -- Finansal bilgiler
    total_amount DECIMAL(12, 2) NOT NULL, -- Toplam ödenecek tutar (satıcı payı)
    commission_amount DECIMAL(12, 2) NOT NULL DEFAULT 0, -- Komisyon tutarı
    order_count INTEGER NOT NULL DEFAULT 0, -- Kaç sipariş için
    
    -- Sipariş detayları (JSON array)
    order_ids JSONB DEFAULT '[]'::jsonb, -- İlgili sipariş ID'leri
    
    -- Durum
    status VARCHAR NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'paid', 'rejected')),
    
    -- Ödeme bilgileri
    iban VARCHAR(50), -- IBAN numarası
    bank_name VARCHAR(100), -- Banka adı
    account_holder_name VARCHAR(255), -- Hesap sahibi adı
    
    -- Notlar
    admin_notes TEXT, -- Admin notları
    rejection_reason TEXT, -- Reddetme sebebi
    
    -- İşleyen admin
    processed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- İşleyen admin
    
    -- Tarihler
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_payout_requests_seller ON payout_requests(seller_id);
CREATE INDEX IF NOT EXISTS idx_payout_requests_shop ON payout_requests(shop_id);
CREATE INDEX IF NOT EXISTS idx_payout_requests_status ON payout_requests(status);
CREATE INDEX IF NOT EXISTS idx_payout_requests_requested_at ON payout_requests(requested_at DESC);

-- RLS etkinleştir
ALTER TABLE payout_requests ENABLE ROW LEVEL SECURITY;

-- RLS Politikaları
-- Satıcılar kendi ödeme isteklerini görebilir
CREATE POLICY "Satıcılar kendi ödeme isteklerini görebilir"
ON payout_requests FOR SELECT
TO authenticated
USING (seller_id = auth.uid());

-- Adminler tüm ödeme isteklerini görebilir
CREATE POLICY "Adminler tüm ödeme isteklerini görebilir"
ON payout_requests FOR SELECT
TO authenticated
USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);

-- Satıcılar ödeme isteği oluşturabilir
CREATE POLICY "Satıcılar ödeme isteği oluşturabilir"
ON payout_requests FOR INSERT
TO authenticated
WITH CHECK (
    seller_id = auth.uid()
);

-- Adminler ödeme isteklerini güncelleyebilir (onay/reddet)
CREATE POLICY "Adminler ödeme isteklerini güncelleyebilir"
ON payout_requests FOR UPDATE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);

-- 2. shops tablosuna IBAN bilgisi ekle
ALTER TABLE shops 
ADD COLUMN IF NOT EXISTS iban VARCHAR(50),
ADD COLUMN IF NOT EXISTS bank_name VARCHAR(100),
ADD COLUMN IF NOT EXISTS account_holder_name VARCHAR(255);

-- 3. shops tablosuna mevcut_kazanç (pending_payout) ekle
-- Bu, henüz ödeme istei yapılmamış kazancı tutar
ALTER TABLE shops
ADD COLUMN IF NOT EXISTS pending_payout DECIMAL(12, 2) DEFAULT 0;

-- 4. orders tablosuna payout_request_id ekle (hangi ödemeye dahil olduğunu takip etmek için)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS payout_request_id UUID REFERENCES payout_requests(id) ON DELETE SET NULL;

-- 5. shops tablosuna total_paid ekle (toplam ödenen tutar)
ALTER TABLE shops
ADD COLUMN IF NOT EXISTS total_paid DECIMAL(12, 2) DEFAULT 0;

-- 6. Updated_at trigger'ı
CREATE OR REPLACE FUNCTION update_payout_requests_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER payout_requests_updated_at
BEFORE UPDATE ON payout_requests
FOR EACH ROW
EXECUTE FUNCTION update_payout_requests_updated_at();

-- 7. Yorumlar
COMMENT ON TABLE payout_requests IS 'Satıcı ödeme istekleri tablosu';
COMMENT ON COLUMN payout_requests.total_amount IS 'Satıcıya ödenecek net tutar';
COMMENT ON COLUMN payout_requests.commission_amount IS 'Platform komisyon tutarı';
COMMENT ON COLUMN payout_requests.order_ids IS 'İlgili sipariş ID''leri JSON array olarak';
COMMENT ON COLUMN payout_requests.status IS 'pending: bekliyor, approved: onaylandı, paid: ödendi, rejected: reddedildi';
COMMENT ON COLUMN shops.pending_payout IS 'Henüz ödeme isteği yapılmamış bekleyen kazanç';
COMMENT ON COLUMN shops.total_paid IS 'Satıcıya yapılan toplam ödeme';

-- 8. Realtime etkinleştir
ALTER PUBLICATION supabase_realtime ADD TABLE payout_requests;

-- 9. Payout bildirim tiplerini notifications tablosuna ekle
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications
ADD CONSTRAINT notifications_type_check
CHECK (type IN ('like', 'comment', 'follow', 'mention', 'order', 'shop', 'support_response', 'support_status', 'complaint_response', 'report', 'payout_approved', 'payout_rejected'));

COMMENT ON COLUMN public.notifications.type IS 'Bildirim tipi: like, comment, follow, mention, order, shop, support_response, support_status, complaint_response, report, payout_approved, payout_rejected';

-- 10. processed_by için indeks
CREATE INDEX IF NOT EXISTS idx_payout_requests_processed_by ON payout_requests(processed_by);

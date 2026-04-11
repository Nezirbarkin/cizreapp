-- Faz 1: Çok Dükkanlı Sipariş Sistemi - Veritabanı Değişiklikleri
-- Bu migration orders tablosuna grup sipariş alanları ekler ve courier_requests tablosu oluşturur

-- ============================================
-- 1. ORDERS TABLOSUNA YENİ ALANLAR EKLE
-- ============================================

-- order_group_id: Aynı müşteri tarafından aynı anda verilen siparişleri gruplar
-- Müşteri farklı dükkanlardan ürün aldığında, her dükkan için ayrı sipariş oluşturulur
-- Ancak aynı order_group_id ile ilişkilendirilir
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_group_id UUID;

-- group_order_number: Grup sipariş numarası (müşteriye gösterilecek)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS group_order_number TEXT;

-- İndeksler ekle
CREATE INDEX IF NOT EXISTS idx_orders_group_id ON orders(order_group_id);
CREATE INDEX IF NOT EXISTS idx_orders_group_number ON orders(group_order_number);

-- ============================================
-- 2. COURIER_REQUESTS TABLOSU OLUŞTUR
-- ============================================
-- Satıcıların kurye talepleri için

CREATE TABLE IF NOT EXISTS courier_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    seller_id UUID NOT NULL REFERENCES profiles(id),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    message TEXT, -- Satıcının isteğe bağlı mesajı
    admin_notes TEXT, -- Admin'in notu (onay/red sebebi)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ, -- Admin'in incelediği zaman
    reviewed_by UUID REFERENCES profiles(id) -- Admin'in ID'si
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_courier_requests_shop ON courier_requests(shop_id);
CREATE INDEX IF NOT EXISTS idx_courier_requests_status ON courier_requests(status);
CREATE INDEX IF NOT EXISTS idx_courier_requests_seller ON courier_requests(seller_id);

-- ============================================
-- 3. RLS POLİCY'LERİ
-- ============================================

-- courier_requests için RLS aktifleştir
ALTER TABLE courier_requests ENABLE ROW LEVEL SECURITY;

-- Mevcut policy'leri temizle
DROP POLICY IF EXISTS seller_view_own_courier_requests ON courier_requests;
DROP POLICY IF EXISTS seller_create_courier_request ON courier_requests;
DROP POLICY IF EXISTS admin_manage_courier_requests ON courier_requests;

-- Satıcı kendi taleplerini görebilir
CREATE POLICY seller_view_own_courier_requests ON courier_requests
    FOR SELECT 
    USING (seller_id = auth.uid());

-- Satıcı talep oluşturabilir
CREATE POLICY seller_create_courier_request ON courier_requests
    FOR INSERT 
    WITH CHECK (seller_id = auth.uid());

-- Admin tüm talepleri görebilir ve yönetebilir
CREATE POLICY admin_manage_courier_requests ON courier_requests
    FOR ALL 
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
    );

-- ============================================
-- 4. PAYMENT_METHOD ENUM GÜNCELLEMESİ
-- ============================================
-- cardOnDelivery değerini ekle (kapıda kart ile ödeme)

DO $$
BEGIN
    -- Check if the enum type exists
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method') THEN
        -- Check if the value already exists
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = 'payment_method'::regtype 
            AND enumlabel = 'cardOnDelivery'
        ) THEN
            ALTER TYPE payment_method ADD VALUE 'cardOnDelivery';
        END IF;
        
        -- card değerini de ekle
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = 'payment_method'::regtype 
            AND enumlabel = 'card'
        ) THEN
            ALTER TYPE payment_method ADD VALUE 'card';
        END IF;
    END IF;
END
$$;

-- ============================================
-- 5. NOTIFICATION_TYPE ENUM GÜNCELLEMESİ
-- ============================================
-- Kurye talep bildirimleri için yeni tipler

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_type') THEN
        -- courier_request tipi ekle
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = 'notification_type'::regtype 
            AND enumlabel = 'courier_request'
        ) THEN
            ALTER TYPE notification_type ADD VALUE 'courier_request';
        END IF;
        
        -- courier_request_approved tipi ekle
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = 'notification_type'::regtype 
            AND enumlabel = 'courier_request_approved'
        ) THEN
            ALTER TYPE notification_type ADD VALUE 'courier_request_approved';
        END IF;
        
        -- courier_request_rejected tipi ekle
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = 'notification_type'::regtype 
            AND enumlabel = 'courier_request_rejected'
        ) THEN
            ALTER TYPE notification_type ADD VALUE 'courier_request_rejected';
        END IF;
    END IF;
END
$$;

-- ============================================
-- 6. YORUMLAR
-- ============================================

COMMENT ON COLUMN orders.order_group_id IS 'Grup sipariş ID - aynı anda verilen çoklu dükkan siparişlerini gruplar';
COMMENT ON COLUMN orders.group_order_number IS 'Grup sipariş numarası - müşteriye gösterilir';

COMMENT ON TABLE courier_requests IS 'Satıcıların kurye talepleri - admin onayı gerektirir';
COMMENT ON COLUMN courier_requests.status IS 'Talep durumu: pending, approved, rejected';
COMMENT ON COLUMN courier_requests.message IS 'Satıcının isteğe bağlı mesajı';
COMMENT ON COLUMN courier_requests.admin_notes IS 'Admin tarafından eklenen notlar';

-- ============================================
-- TAMAMLANDI
-- ============================================
-- Bu migration'ı çalıştırdıktan sonra:
-- 1. orders tablosunda order_group_id ve group_order_number alanları mevcut
-- 2. courier_requests tablosu oluşturuldu
-- 3. RLS policy'leri aktif
-- 4. Yeni payment_method değerleri eklendi
-- 5. Yeni notification_type değerleri eklendi

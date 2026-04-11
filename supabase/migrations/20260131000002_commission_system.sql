-- CizreApp Komisyon Sistemi Migration
-- Bu migration, siparişlere admin komisyonu ve teslimat ücreti kesintilerini ekler

-- =====================================================
-- 1. Orders Tablosuna Komisyon Alanları Ekle
-- =====================================================

-- Komisyon durumu (pending: bekliyor, collected: tahsil edildi, debt: borç, waived: affedildi)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS commission_status VARCHAR DEFAULT 'pending'
CHECK (commission_status IN ('pending', 'collected', 'debt', 'waived'));

-- Admin komisyon tutarı (sipariş tutarının %'i)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS admin_commission DECIMAL(12, 2) DEFAULT 0;

-- Admin teslimat ücreti (kuryesi olmayan satıcılardan kesilen)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS admin_delivery_fee DECIMAL(12, 2) DEFAULT 0;

-- Satıcıya ödenen net tutar
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS seller_net_amount DECIMAL(12, 2) DEFAULT 0;

-- Komisyon borç tutarı (kuryesi olan + kapıda ödeme)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS commission_debt DECIMAL(12, 2) DEFAULT 0;

-- Komisyon hesaplandığı tarih
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS commission_calculated_at TIMESTAMPTZ;

-- Yorumlar
COMMENT ON COLUMN orders.commission_status IS 'Komisyon durumu: pending=bekliyor, collected=tahsil edildi, debt=borç, waived=affedildi';
COMMENT ON COLUMN orders.admin_commission IS 'Adminin kestiği komisyon tutarı';
COMMENT ON COLUMN orders.admin_delivery_fee IS 'Adminin kestiği teslimat ücreti (kuryesi olmayanlar)';
COMMENT ON COLUMN orders.seller_net_amount IS 'Satıcıya ödenen net tutar';
COMMENT ON COLUMN orders.commission_debt IS 'Tahsil edilecek komisyon borcu';
COMMENT ON COLUMN orders.commission_calculated_at IS 'Komisyonun hesaplandığı tarih';

-- =====================================================
-- 2. System Settings Tablosu
-- =====================================================

CREATE TABLE IF NOT EXISTS system_settings (
    key VARCHAR PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE system_settings IS 'Sistem genelindeki ayarlar';

-- Varsayılan admin komisyon oranı
INSERT INTO system_settings (key, value, description)
VALUES ('admin_commission_rate', '10', 'Admin komisyon oranı (%) - Tamsayı')
ON CONFLICT (key) DO NOTHING;

-- Varsayılan teslimat ücreti (kuryesi olmayanlar için)
INSERT INTO system_settings (key, value, description)
VALUES ('default_delivery_fee', '30', 'Varsayılan teslimat ücreti (₺)')
ON CONFLICT (key) DO NOTHING;

-- =====================================================
-- 3. Komisyon Hesaplama Fonksiyonu
-- =====================================================

CREATE OR REPLACE FUNCTION calculate_order_commission(
    p_order_id UUID,
    p_admin_commission_rate DECIMAL DEFAULT NULL
) RETURNS TABLE(
    admin_commission DECIMAL,
    admin_delivery_fee DECIMAL,
    seller_net_amount DECIMAL,
    commission_status VARCHAR,
    commission_debt DECIMAL
) AS $$
DECLARE
    v_order RECORD;
    v_shop RECORD;
    v_admin_comm_rate DECIMAL;
    v_admin_comm DECIMAL;
    v_admin_delivery DECIMAL;
    v_net_amount DECIMAL;
    v_comm_status VARCHAR;
    v_comm_debt DECIMAL;
BEGIN
    -- Sipariş ve dükkan bilgilerini al
    SELECT * INTO v_order FROM orders WHERE id = p_order_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sipariş bulunamadı: %', p_order_id;
    END IF;
    
    SELECT * INTO v_shop FROM shops WHERE id = v_order.shop_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dükkan bulunamadı: %', v_order.shop_id;
    END IF;
    
    -- Admin komisyon oranını al
    IF p_admin_commission_rate IS NOT NULL THEN
        v_admin_comm_rate := p_admin_commission_rate;
    ELSE
        SELECT CAST(value AS DECIMAL)
        INTO v_admin_comm_rate
        FROM system_settings
        WHERE key = 'admin_commission_rate';
        
        IF v_admin_comm_rate IS NULL THEN
            v_admin_comm_rate := 10; -- Varsayılan %10
        END IF;
    END IF;
    
    -- Komisyon hesapla
    v_admin_comm := ROUND(v_order.subtotal * v_admin_comm_rate / 100.0, 2);
    
    -- Kurye durumu ve ödeme yöntemine göre hesapla
    IF v_shop.has_own_courier = false OR v_shop.has_own_courier IS NULL THEN
        -- Kuryesi yok - teslimat ücretini kes
        v_admin_delivery := v_order.delivery_fee;
        v_comm_status := 'collected';
        v_comm_debt := 0;
    ELSE
        -- Kuryesi var - teslimat ücretini kesme
        v_admin_delivery := 0;
        
        IF v_order.payment_method IN ('cash', 'cardOnDelivery') THEN
            -- Kapıda ödeme - borç olarak işaretle
            v_comm_status := 'debt';
            v_comm_debt := v_admin_comm;
        ELSE
            -- Online ödeme - tahsil et
            v_comm_status := 'collected';
            v_comm_debt := 0;
        END IF;
    END IF;
    
    -- Net tutar hesapla
    v_net_amount := v_order.subtotal - v_admin_comm - v_admin_delivery;
    
    RETURN QUERY SELECT v_admin_comm, v_admin_delivery, v_net_amount, v_comm_status, v_comm_debt;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_order_commission IS 'Sipariş için komisyon hesaplar';

-- =====================================================
-- 4. Otomatik Komisyon Hesaplama Trigger
-- =====================================================

CREATE OR REPLACE FUNCTION auto_calculate_commission()
RETURNS TRIGGER AS $$
DECLARE
    v_commission RECORD;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO v_commission
        FROM calculate_order_commission(NEW.id);
        
        NEW.admin_commission := v_commission.admin_commission;
        NEW.admin_delivery_fee := v_commission.admin_delivery_fee;
        NEW.seller_net_amount := v_commission.seller_net_amount;
        NEW.commission_status := v_commission.commission_status;
        NEW.commission_debt := v_commission.commission_debt;
        NEW.commission_calculated_at := NOW();
        
        -- Dükkanın pending_payout tutarını güncelle
        IF NEW.commission_status = 'collected' THEN
            UPDATE shops
            SET pending_payout = COALESCE(pending_payout, 0) + NEW.seller_net_amount
            WHERE id = NEW.shop_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION auto_calculate_commission IS 'Sipariş oluşturulduğunda otomatik komisyon hesaplar';

DROP TRIGGER IF EXISTS orders_auto_calculate_commission ON orders;
CREATE TRIGGER orders_auto_calculate_commission
    BEFORE INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION auto_calculate_commission();

-- =====================================================
-- 5. Admin Komisyon Raporu Fonksiyonu
-- =====================================================

CREATE OR REPLACE FUNCTION get_admin_commission_report(
    p_start_date TIMESTAMPTZ DEFAULT NOW() - INTERVAL '30 days',
    p_end_date TIMESTAMPTZ DEFAULT NOW()
) RETURNS TABLE(
    total_orders BIGINT,
    total_amount DECIMAL,
    total_commission DECIMAL,
    collected_commission DECIMAL,
    debt_commission DECIMAL,
    waived_commission DECIMAL,
    total_delivery_fee DECIMAL,
    total_net_admin DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*)::BIGINT,
        COALESCE(SUM(subtotal), 0),
        COALESCE(SUM(admin_commission), 0),
        COALESCE(SUM(CASE WHEN commission_status = 'collected' THEN admin_commission ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN commission_status = 'debt' THEN admin_commission ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN commission_status = 'waived' THEN admin_commission ELSE 0 END), 0),
        COALESCE(SUM(admin_delivery_fee), 0),
        COALESCE(SUM(admin_commission + admin_delivery_fee), 0)
    FROM orders
    WHERE created_at BETWEEN p_start_date AND p_end_date
    AND status != 'cancelled';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_admin_commission_report IS 'Admin komisyon raporunu döndürür';

-- =====================================================
-- 6. Satıcı Komisyon Özeti Fonksiyonu
-- =====================================================

CREATE OR REPLACE FUNCTION get_seller_commission_summary(
    p_seller_id UUID,
    p_start_date TIMESTAMPTZ DEFAULT NOW() - INTERVAL '30 days',
    p_end_date TIMESTAMPTZ DEFAULT NOW()
) RETURNS TABLE(
    total_orders BIGINT,
    total_sales DECIMAL,
    total_commission DECIMAL,
    collected_commission DECIMAL,
    debt_commission DECIMAL,
    net_earnings DECIMAL,
    pending_payout DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(o.id)::BIGINT,
        COALESCE(SUM(o.subtotal), 0),
        COALESCE(SUM(o.admin_commission), 0),
        COALESCE(SUM(CASE WHEN o.commission_status = 'collected' THEN o.admin_commission ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN o.commission_status = 'debt' THEN o.admin_commission ELSE 0 END), 0),
        COALESCE(SUM(o.seller_net_amount), 0),
        COALESCE(s.pending_payout, 0)
    FROM shops s
    LEFT JOIN orders o ON o.shop_id = s.id AND o.created_at BETWEEN p_start_date AND p_end_date AND o.status != 'cancelled'
    WHERE s.owner_id = p_seller_id
    GROUP BY s.id, s.pending_payout;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_seller_commission_summary IS 'Satıcı komisyon özetini döndürür';

-- =====================================================
-- 7. Borçlu Siparişler View
-- =====================================================

CREATE OR REPLACE VIEW v_debt_orders AS
SELECT 
    o.id,
    o.order_number_int,
    o.shop_id,
    s.name as shop_name,
    s.owner_id,
    o.subtotal,
    o.admin_commission,
    o.commission_debt,
    o.payment_method,
    o.status,
    o.created_at
FROM orders o
JOIN shops s ON s.id = o.shop_id
WHERE o.commission_status = 'debt'
AND o.status != 'cancelled'
ORDER BY o.created_at DESC;

COMMENT ON VIEW v_debt_orders IS 'Borçlu siparişler listesi';

-- =====================================================
-- 8. Admin Komisyon Dashboard View
-- =====================================================

CREATE OR REPLACE VIEW v_admin_commission_dashboard AS
SELECT 
    DATE(o.created_at) as date,
    COUNT(*) as order_count,
    SUM(o.subtotal) as total_sales,
    SUM(o.admin_commission) as total_commission,
    SUM(CASE WHEN o.commission_status = 'collected' THEN o.admin_commission ELSE 0 END) as collected_commission,
    SUM(CASE WHEN o.commission_status = 'debt' THEN o.admin_commission ELSE 0 END) as debt_commission,
    SUM(o.admin_delivery_fee) as total_delivery_fee,
    SUM(o.admin_commission + o.admin_delivery_fee) as total_admin_revenue
FROM orders o
WHERE o.status != 'cancelled'
GROUP BY DATE(o.created_at)
ORDER BY date DESC;

COMMENT ON VIEW v_admin_commission_dashboard IS 'Admin komisyon dashboard verileri';

-- =====================================================
-- 9. System Settings Updated_at Trigger
-- =====================================================

CREATE OR REPLACE FUNCTION update_system_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS system_settings_updated_at ON system_settings;
CREATE TRIGGER system_settings_updated_at
    BEFORE UPDATE ON system_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_system_settings_updated_at();

-- =====================================================
-- 10. İndeksler
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_orders_commission_status ON orders(commission_status);
CREATE INDEX IF NOT EXISTS idx_orders_admin_commission ON orders(admin_commission);
CREATE INDEX IF NOT EXISTS idx_orders_commission_debt ON orders(commission_debt) WHERE commission_debt > 0;
CREATE INDEX IF NOT EXISTS idx_orders_commission_calculated_at ON orders(commission_calculated_at DESC);
CREATE INDEX IF NOT EXISTS idx_system_settings_key ON system_settings(key);

-- =====================================================
-- 11. RLS Politikaları
-- =====================================================

-- Adminler komisyon raporlarını görebilir
DROP POLICY IF EXISTS "Adminler komisyon verilerini görebilir" ON orders;
CREATE POLICY "Adminler komisyon verilerini görebilir"
ON orders FOR SELECT
TO authenticated
USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);

-- Satıcılar kendi komisyon verilerini görebilir
DROP POLICY IF EXISTS "Satıcılar kendi komisyonunu görebilir" ON orders;
CREATE POLICY "Satıcılar kendi komisyonunu görebilir"
ON orders FOR SELECT
TO authenticated
USING (
    shop_id IN (SELECT id FROM shops WHERE owner_id = auth.uid())
);

-- System settings için RLS
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Adminler system_settings görebilir" ON system_settings;
CREATE POLICY "Adminler system_settings görebilir"
ON system_settings FOR SELECT
TO authenticated
USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);

DROP POLICY IF EXISTS "Adminler system_settings güncelleyebilir" ON system_settings;
CREATE POLICY "Adminler system_settings güncelleyebilir"
ON system_settings FOR ALL
TO authenticated
USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
)
WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
);

-- =====================================================
-- 12. Realtime
-- =====================================================

ALTER PUBLICATION supabase_realtime ADD TABLE system_settings;

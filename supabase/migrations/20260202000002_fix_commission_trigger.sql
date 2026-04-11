-- =====================================================
-- FIX: Komisyon Trigger Hatası Düzeltme
-- =====================================================
-- Sorun: BEFORE INSERT trigger'ında NEW.id kullanılarak 
-- orders tablosundan SELECT yapılıyordu, ama henüz inserted değil.
--
-- Çözüm: NEW değişkeninden doğrudan değerleri al

CREATE OR REPLACE FUNCTION auto_calculate_commission()
RETURNS TRIGGER AS $$
DECLARE
    v_shop RECORD;
    v_admin_comm_rate DECIMAL;
    v_admin_comm DECIMAL;
    v_admin_delivery DECIMAL;
    v_net_amount DECIMAL;
    v_comm_status VARCHAR;
    v_comm_debt DECIMAL;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Dükkan bilgilerini al
        SELECT * INTO v_shop FROM shops WHERE id = NEW.shop_id;
        
        IF NOT FOUND THEN
            -- Dükkan bulunamazsa varsayılan değerleri kullan
            v_shop.has_own_courier := true;
        END IF;
        
        -- Admin komisyon oranını al
        SELECT CAST(value AS DECIMAL)
        INTO v_admin_comm_rate
        FROM system_settings
        WHERE key = 'admin_commission_rate';
        
        IF v_admin_comm_rate IS NULL THEN
            v_admin_comm_rate := 10; -- Varsayılan %10
        END IF;
        
        -- Komisyon hesapla
        v_admin_comm := ROUND(NEW.subtotal * v_admin_comm_rate / 100.0, 2);
        
        -- Kurye durumu ve ödeme yöntemine göre hesapla
        IF v_shop.has_own_courier = false OR v_shop.has_own_courier IS NULL THEN
            -- Kuryesi yok - teslimat ücretini kes
            v_admin_delivery := COALESCE(NEW.delivery_fee, 0);
            v_comm_status := 'collected';
            v_comm_debt := 0;
        ELSE
            -- Kuryesi var - teslimat ücretini kesme
            v_admin_delivery := 0;
            
            IF NEW.payment_method IN ('cash', 'cardOnDelivery') THEN
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
        v_net_amount := NEW.subtotal - v_admin_comm - v_admin_delivery;
        
        -- Değerleri ata
        NEW.admin_commission := v_admin_comm;
        NEW.admin_delivery_fee := v_admin_delivery;
        NEW.seller_net_amount := v_net_amount;
        NEW.commission_status := v_comm_status;
        NEW.commission_debt := v_comm_debt;
        NEW.commission_calculated_at := NOW();
        
        -- Dükkanın pending_payout tutarını güncelle (AFTER TRIGGER'da yapılacak)
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION auto_calculate_commission IS 'Sipariş oluşturulduğunda otomatik komisyon hesaplar (FIXED)';

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS orders_auto_calculate_commission ON orders;
CREATE TRIGGER orders_auto_calculate_commission
    BEFORE INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION auto_calculate_commission();

-- =====================================================
-- After INSERT Trigger - Pending Payout Güncelleme
-- =====================================================
-- Shop pending_payout güncellemesi AFTER INSERT'te yapılmalı
CREATE OR REPLACE FUNCTION update_shop_pending_payout()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.commission_status = 'collected' THEN
        UPDATE shops
        SET pending_payout = COALESCE(pending_payout, 0) + NEW.seller_net_amount
        WHERE id = NEW.shop_id;
    END IF;
    
    IF TG_OP = 'UPDATE' AND OLD.commission_status != NEW.commission_status THEN
        IF NEW.commission_status = 'collected' AND OLD.commission_status != 'collected' THEN
            -- Borç tahsil edildi -> pending payout'a ekle
            UPDATE shops
            SET pending_payout = COALESCE(pending_payout, 0) + NEW.seller_net_amount
            WHERE id = NEW.shop_id;
        ELSIF OLD.commission_status = 'collected' AND NEW.commission_status != 'collected' THEN
            -- Kaldırıldı -> pending payout'dan çıkar
            UPDATE shops
            SET pending_payout = GREATEST(COALESCE(pending_payout, 0) - NEW.seller_net_amount, 0)
            WHERE id = NEW.shop_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS orders_update_shop_pending_payout ON orders;
CREATE TRIGGER orders_update_shop_pending_payout
    AFTER INSERT OR UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_shop_pending_payout();

COMMENT ON FUNCTION update_shop_pending_payout IS 'Sipariş durumuna göre dükkan pending payoutunu günceller';

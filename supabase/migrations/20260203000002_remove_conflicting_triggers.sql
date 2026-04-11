-- =====================================================
-- FIX: Çakışan Komisyon Trigger'larını Kaldır
-- =====================================================
-- Sorun: 20260203000000_fix_linter_warnings.sql'de eski komisyon sistemi
-- trigger'ları yeniden oluşturulmuş ve seller_earning alanını kullanıyor.
-- Ancak orders tablosunda seller_earning yok, seller_net_amount var.
--
-- Çözüm: Eski trigger'ları kaldır, yeni sistemi koru

-- =====================================================
-- 1. Eski Trigger'ları Kaldır
-- =====================================================

-- Eski auto_calculate_commission trigger'ını kaldır
DROP TRIGGER IF EXISTS orders_auto_calculate_commission ON public.orders;

-- Eski update_shop_pending_payout trigger'ını kaldır  
DROP TRIGGER IF EXISTS orders_update_shop_pending_payout ON public.orders;

-- =====================================================
-- 2. Yeni Sistemi Yeniden Aktif Et
-- =====================================================

-- Yeni auto_calculate_commission fonksiyonu (20260202000002'den)
CREATE OR REPLACE FUNCTION public.auto_calculate_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shop RECORD;
    v_admin_comm_rate NUMERIC;
    v_admin_comm NUMERIC;
    v_admin_delivery NUMERIC;
    v_net_amount NUMERIC;
    v_comm_status VARCHAR;
    v_comm_debt NUMERIC;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Dükkan bilgilerini al
        SELECT * INTO v_shop FROM public.shops WHERE id = NEW.shop_id;
        
        IF NOT FOUND THEN
            -- Dükkan bulunamazsa varsayılan değerleri kullan
            v_shop.has_own_courier := true;
        END IF;
        
        -- Admin komisyon oranını al
        SELECT CAST(value AS NUMERIC)
        INTO v_admin_comm_rate
        FROM public.system_settings
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
    END IF;
    
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.auto_calculate_commission IS 'Sipariş oluşturulduğunda otomatik komisyon hesaplar (YENİ SİSTEM)';

-- Trigger'ı yeniden oluştur
CREATE TRIGGER orders_auto_calculate_commission
    BEFORE INSERT ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.auto_calculate_commission();

-- =====================================================
-- 3. Pending Payout Güncelleme Trigger
-- =====================================================

-- Yeni update_shop_pending_payout fonksiyonu
CREATE OR REPLACE FUNCTION public.update_shop_pending_payout()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.commission_status = 'collected' THEN
        UPDATE public.shops
        SET pending_payout = COALESCE(pending_payout, 0) + NEW.seller_net_amount
        WHERE id = NEW.shop_id;
    END IF;
    
    IF TG_OP = 'UPDATE' AND OLD.commission_status != NEW.commission_status THEN
        IF NEW.commission_status = 'collected' AND OLD.commission_status != 'collected' THEN
            -- Borç tahsil edildi -> pending payout'a ekle
            UPDATE public.shops
            SET pending_payout = COALESCE(pending_payout, 0) + NEW.seller_net_amount
            WHERE id = NEW.shop_id;
        ELSIF OLD.commission_status = 'collected' AND NEW.commission_status != 'collected' THEN
            -- Kaldırıldı -> pending payout'dan çıkar
            UPDATE public.shops
            SET pending_payout = GREATEST(COALESCE(pending_payout, 0) - NEW.seller_net_amount, 0)
            WHERE id = NEW.shop_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.update_shop_pending_payout IS 'Sipariş durumuna göre dükkan pending payoutunu günceller (YENİ SİSTEM)';

-- Trigger'ı yeniden oluştur
CREATE TRIGGER orders_update_shop_pending_payout
    AFTER INSERT OR UPDATE ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.update_shop_pending_payout();

-- =====================================================
-- 4. Eski Alanları Temizle (Eğer Varsa)
-- =====================================================

-- NOT: Eğer orders tablosunda eski sistemden kalan alanlar varsa,
-- bunları kaldırabilirsiniz. Ancak önce kontrol edin.

-- Eski alanları kontrol et:
DO $$
BEGIN
    -- seller_earning alanı varsa sil
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'orders' 
        AND column_name = 'seller_earning'
    ) THEN
        EXECUTE 'ALTER TABLE public.orders DROP COLUMN IF EXISTS seller_earning';
        RAISE NOTICE 'seller_earning alanı kaldırıldı';
    END IF;
    
    -- commission_rate alanı varsa sil (shops'ta kalabilir)
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'orders' 
        AND column_name = 'commission_rate'
    ) THEN
        EXECUTE 'ALTER TABLE public.orders DROP COLUMN IF EXISTS commission_rate';
        RAISE NOTICE 'commission_rate alanı kaldırıldı';
    END IF;
    
    -- commission_amount alanı varsa sil
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'orders' 
        AND column_name = 'commission_amount'
    ) THEN
        EXECUTE 'ALTER TABLE public.orders DROP COLUMN IF EXISTS commission_amount';
        RAISE NOTICE 'commission_amount alanı kaldırıldı';
    END IF;
END $$;

-- =====================================================
-- 5. Doğrulama
-- =====================================================

-- Aktif trigger'ları göster
SELECT 
    tgname as trigger_name,
    tgenabled as is_enabled,
    pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgrelid = 'public.orders'::regclass
AND tgname LIKE '%commission%'
ORDER BY tgname;

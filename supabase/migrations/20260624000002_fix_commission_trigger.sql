-- ============================================
-- FIX: create_seller_earnings_on_delivery trigger'ında commission_percent hatası
-- ============================================
-- Hata: record "v_shop" has no field "commission_percent"
-- Neden: shops tablosunda alan adı commission_rate, trigger'da commission_percent yazılmış

-- Trigger fonksiyonunu yeniden oluştur
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
            -- FIX: commission_percent -> commission_rate (shops tablosundaki gerçek alan adı)
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
                NOW() + INTERVAL '24 hours'
            )
            ON CONFLICT (order_id) DO NOTHING;
            
            RAISE NOTICE 'Seller earnings created for order %', v_order.order_number;
        END IF;
    END IF;
    
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Trigger hata verirse sipariş güncellemesini engelleme
    RAISE NOTICE 'create_seller_earnings hatası (görmezden gelindi): %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS trigger_create_seller_earnings ON orders;
CREATE TRIGGER trigger_create_seller_earnings
    AFTER UPDATE OF status ON orders
    FOR EACH ROW
    EXECUTE FUNCTION create_seller_earnings_on_delivery();

-- seller_earnings tablosunda unique constraint ekle (order_id) - duplicate engeli
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'seller_earnings_order_id_key'
        AND table_name = 'seller_earnings'
    ) THEN
        ALTER TABLE seller_earnings ADD CONSTRAINT seller_earnings_order_id_key UNIQUE (order_id);
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Unique constraint eklenemedi: %', SQLERRM;
END $$;

COMMENT ON FUNCTION create_seller_earnings_on_delivery IS 'Sipariş teslim edildiğinde satıcı kazancı oluşturur (commission_percent hatası düzeltildi)';

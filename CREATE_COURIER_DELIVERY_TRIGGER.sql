-- ============================================
-- KURYE TESLİM EDİĞİNDE SIPARIŞ DURUMUNU GÜNCELLEYEN TRIGGER
-- ============================================

-- 1. Trigger fonksiyonu oluştur
CREATE OR REPLACE FUNCTION update_order_status_on_courier_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Kurye atama durumu 'delivered' olduğunda sipariş durumunu da güncelle
    IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
        UPDATE public.orders
        SET 
            status = 'delivered',
            delivered_at = NOW(),
            updated_at = NOW()
        WHERE id = NEW.order_id
        AND status != 'delivered';
        
        RAISE NOTICE 'Order % status updated to delivered by courier assignment', NEW.order_id;
    END IF;
    
    -- Kurye atama durumu 'on_the_way' olduğunda sipariş durumunu da güncelle
    IF NEW.status = 'on_the_way' AND (OLD.status IS NULL OR OLD.status != 'on_the_way') THEN
        UPDATE public.orders
        SET 
            status = 'on_the_way',
            updated_at = NOW()
        WHERE id = NEW.order_id
        AND status IN ('confirmed', 'preparing', 'ready');
        
        RAISE NOTICE 'Order % status updated to on_the_way by courier assignment', NEW.order_id;
    END IF;
    
    RETURN NEW;
END;
$$;

-- 2. Mevcut trigger'ı sil (varsa)
DROP TRIGGER IF EXISTS trigger_courier_delivery_update ON public.courier_assignments;

-- 3. Trigger oluştur
CREATE TRIGGER trigger_courier_delivery_update
    AFTER UPDATE ON public.courier_assignments
    FOR EACH ROW
    EXECUTE FUNCTION update_order_status_on_courier_delivery();

-- 4. Doğrulama
SELECT 'Courier delivery trigger created successfully' as status;
SELECT trigger_name, event_object_table 
FROM information_schema.triggers 
WHERE trigger_name = 'trigger_courier_delivery_update';
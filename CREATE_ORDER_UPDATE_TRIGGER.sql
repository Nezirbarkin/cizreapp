-- ============================================================================
-- KURYE ATANDIĞINDA SİPARİŞ DURUMUNU OTOMATİK GÜNCELLE
-- ============================================================================

-- Trigger fonksiyonu oluştur
CREATE OR REPLACE FUNCTION update_order_on_courier_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Kurye atandığında sipariş durumunu on_the_way yap
    IF NEW.status = 'assigned' AND (OLD.status IS NULL OR OLD.status = 'pending') THEN
        UPDATE public.orders
        SET 
            status = 'on_the_way',
            updated_at = NOW()
        WHERE id = NEW.order_id;
        
        RAISE NOTICE 'Order % status updated to on_the_way after courier assignment', NEW.order_id;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Mevcut trigger'ı sil (varsa)
DROP TRIGGER IF EXISTS trigger_order_on_courier_assignment ON public.courier_assignments;

-- Trigger oluştur
CREATE TRIGGER trigger_order_on_courier_assignment
    AFTER INSERT ON public.courier_assignments
    FOR EACH ROW
    EXECUTE FUNCTION update_order_on_courier_assignment();

-- Doğrulama
SELECT 'Trigger created: update_order_on_courier_assignment' as status;
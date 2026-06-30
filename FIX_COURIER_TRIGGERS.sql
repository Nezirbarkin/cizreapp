-- ============================================================================
-- SORUN: Database trigger'ı sipariş atandığında orders.status = 'on_the_way' yapıyor
-- Bu yüzden kurye panelinde sipariş görünmüyordu!
-- ============================================================================

-- Trigger fonksiyonunu güncelle
-- NOT: Artık orders.status = 'on_the_way' yapmıyoruz
-- Kurye siparişi kabul ettiğinde (_acceptOrder) zaten on_the_way yapılıyor

CREATE OR REPLACE FUNCTION update_order_on_courier_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Kurye atandığında sipariş durumunu güncelleme
    -- orders.status = 'on_the_way' sadece kurye siparişi kabul ettiğinde yapılmalı
    -- Aksi halde sipariş kurye panelinin "Atanabilir Siparişler" listesinden düşer
    
    -- Sadece log mesajı yaz
    RAISE NOTICE 'Courier assignment created for order % - status NOT changed to on_the_way', NEW.order_id;
    
    RETURN NEW;
END;
$$;

-- Trigger zaten varsa yeniden oluştur (fonksiyon değiştiği için gerekli)
DROP TRIGGER IF EXISTS trigger_order_on_courier_assignment ON public.courier_assignments;

CREATE TRIGGER trigger_order_on_courier_assignment
    AFTER INSERT ON public.courier_assignments
    FOR EACH ROW
    EXECUTE FUNCTION update_order_on_courier_assignment();

-- Doğrulama
SELECT 'Trigger updated: orders.status is NOT changed to on_the_way anymore' as status;

-- ============================================================================
-- MEVCUT SİPARİŞLERİ DÜZELT
-- ============================================================================

-- courier_assignments'a atanmış ama orders.status = 'on_the_way' olan siparişleri ready yap
UPDATE orders
SET status = 'ready', updated_at = NOW()
WHERE status = 'on_the_way'
AND EXISTS (
    SELECT 1 FROM courier_assignments ca 
    WHERE ca.order_id = orders.id 
    AND ca.status = 'assigned'
);

-- Doğrulama
SELECT status, COUNT(*) as count FROM orders GROUP BY status;

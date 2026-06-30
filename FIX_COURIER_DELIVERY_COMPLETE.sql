-- ============================================================================
-- KURYE TESLİMAT SİSTEMİ DÜZELTMELERİ
-- ============================================================================

-- ============================================================================
-- SORUN 1: Database Trigger - orders.status yanlış güncelleniyor
-- ============================================================================

-- Trigger fonksiyonunu güncelle
-- Artık orders.status = 'on_the_way' yapmıyor
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
    RAISE NOTICE 'Courier assignment created for order % - status NOT changed to on_the_way', NEW.order_id;
    RETURN NEW;
END;
$$;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS trigger_order_on_courier_assignment ON public.courier_assignments;
CREATE TRIGGER trigger_order_on_courier_assignment
    AFTER INSERT ON public.courier_assignments
    FOR EACH ROW
    EXECUTE FUNCTION update_order_on_courier_assignment();

-- ============================================================================
-- SORUN 2: Mevcut siparişleri düzelt
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

-- ============================================================================
-- DOĞRULAMA
-- ============================================================================

-- Sipariş durumlarını kontrol et
SELECT status, COUNT(*) as count FROM orders GROUP BY status;

-- Kurye atanmış siparişlerin durumunu kontrol et
SELECT 
    o.id,
    o.status AS order_status,
    o.total,
    ca.status AS assignment_status,
    p.full_name AS courier_name
FROM orders o
JOIN courier_assignments ca ON ca.order_id = o.id
LEFT JOIN profiles p ON p.id = ca.courier_id
WHERE o.status != 'delivered' AND o.status != 'cancelled'
ORDER BY o.created_at DESC
LIMIT 10;

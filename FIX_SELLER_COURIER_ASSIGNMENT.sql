-- ============================================================================
-- SORUNUN KÖK NEDENİ VE ÇÖZÜMÜ
-- ============================================================================

-- SORUNUN KÖK NEDENİ:
-- Satıcı kurye çağırdığında orders.status = 'on_the_way' yapılıyordu.
-- Kurye paneli "Atanabilir Siparişler" listesinde sadece 
-- status IN ('confirmed', 'preparing', 'ready') olan siparişleri gösteriyor.
-- 'on_the_way' statüsü bu listede OLMAYI ÇÜNKEN sipariş kurye panelinde görünmüyordu.

-- ÇÖZÜM:
-- 1. Dart kodunda düzeltme yapıldı (orders.status güncellenmiyor, sadece courier_assignments ekleniyor)
-- 2. Mevcut siparişlerin status='on_the_way' olanları 'ready' yap

-- ============================================================================
-- TEST: Mevcut durumu kontrol et
-- ============================================================================

-- 1) Sipariş ve courier_assignments detaylı kontrol
SELECT 
    o.id AS order_id,
    o.status AS order_status,
    o.updated_at,
    ca.id AS assignment_id,
    ca.courier_id AS assignment_courier_id,
    ca.status AS assignment_status,
    p.full_name AS courier_name
FROM orders o
LEFT JOIN courier_assignments ca ON ca.order_id = o.id
LEFT JOIN profiles p ON p.id = ca.courier_id
WHERE o.id = '49ca4a0f-9e50-413a-bf72-f212485322a9';

-- 2) Siparişlerim sorgusunu simüle et (kurye panelindeki gibi)
SELECT 
    ca.id AS assignment_id,
    ca.status AS assignment_status,
    o.id AS order_id,
    o.status AS order_status,
    o.total
FROM courier_assignments ca
JOIN orders o ON ca.order_id = o.id
WHERE ca.courier_id = 'ce598db8-4e36-4f0c-9fae-50f197162d87'
AND ca.status IN ('assigned', 'picked_up', 'on_the_way', 'delivered')
ORDER BY ca.assigned_at DESC;

-- ============================================================================
-- DÜZELTME: orders.status 'on_the_way' olanları 'ready' yap
-- ============================================================================

UPDATE orders
SET status = 'ready', updated_at = NOW()
WHERE id = '49ca4a0f-9e50-413a-bf72-f212485322a9'
AND status = 'on_the_way';

-- ============================================================================
-- DOĞRULAMA
-- ============================================================================

-- Düzeltmeden sonra sipariş durumu
SELECT 
    o.id,
    o.status AS order_status,
    ca.status AS assignment_status
FROM orders o
LEFT JOIN courier_assignments ca ON ca.order_id = o.id
WHERE o.id = '49ca4a0f-9e50-413a-bf72-f212485322a9';

-- Kurye panelinin göreceği sipariş (Siparişlerim)
SELECT 
    ca.id,
    ca.status,
    o.status,
    o.total
FROM courier_assignments ca
JOIN orders o ON ca.order_id = o.id
WHERE ca.courier_id = 'ce598db8-4e36-4f0c-9fae-50f197162d87'
AND ca.status IN ('assigned', 'picked_up', 'on_the_way', 'delivered');

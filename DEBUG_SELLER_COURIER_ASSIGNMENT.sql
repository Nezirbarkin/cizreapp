-- ============================================================================
-- SORUN ANALİZİ: Kuryesi olmayan satıcılardan sipariş kuryeye düşmüyor
-- ============================================================================

-- 1) Sipariş ve courier_assignments detaylı kontrol
SELECT 
    o.id AS order_id,
    o.order_number,
    o.status AS order_status,
    o.courier_id AS order_courier_id,
    o.updated_at AS order_updated_at,
    ca.id AS assignment_id,
    ca.courier_id AS assignment_courier_id,
    ca.status AS assignment_status,
    ca.assigned_at,
    p.full_name AS courier_name,
    p.is_online AS courier_is_online,
    s.name AS shop_name,
    s.has_own_courier
FROM orders o
LEFT JOIN courier_assignments ca ON ca.order_id = o.id
LEFT JOIN profiles p ON p.id = ca.courier_id
LEFT JOIN shops s ON s.id = o.shop_id
WHERE o.id = '49ca4a0f-9e50-413a-bf72-f212485322a9';

-- 2) orders.courier_id NULL mı? (BU SORUN OLABİLİR!)
SELECT 
    o.id,
    o.status,
    o.courier_id,
    o.updated_at
FROM orders o
WHERE o.id = '49ca4a0f-9e50-413a-bf72-f212485322a9';

-- 3) courier_assignments kaydı doğru kurye ID'si ile mi?
SELECT 
    ca.id,
    ca.order_id,
    ca.courier_id,
    ca.status,
    p.full_name,
    p.role,
    p.is_online
FROM courier_assignments ca
JOIN profiles p ON p.id = ca.courier_id
WHERE ca.order_id = '49ca4a0f-9e50-413a-bf72-f212485322a9';

-- 4) Kurye panelinin gördüğü sorguyu simüle et
-- Aktif siparişler (bu kuryeye atanmış olanlar)
SELECT 
    ca.id AS assignment_id,
    ca.status AS assignment_status,
    ca.courier_id,
    o.id AS order_id,
    o.status AS order_status,
    o.courier_id AS order_courier_id
FROM courier_assignments ca
JOIN orders o ON ca.order_id = o.id
WHERE ca.courier_id = 'ce598db8-4e36-4f0c-9fae-50f197162d87'
AND ca.status IN ('assigned', 'picked_up', 'on_the_way', 'delivered')
ORDER BY ca.assigned_at DESC;

-- 5) Kurye panelinin orders tablosunu nasıl gördüğünü kontrol et
-- RLS devreye giriyor mu?
SELECT 
    o.id,
    o.status,
    o.courier_id
FROM orders o
WHERE o.id = '49ca4a0f-9e50-413a-bf72-f212485322a9';

-- 6) Sorun: orders.courier_id güncellenmemiş olabilir!
-- _callCourierForOrder fonksiyonu orders.courier_id'yi güncellemiyor
-- Sadece status='on_the_way' yapıyor

-- 7) ÇÖZÜM: orders tablosundaki courier_id'yi de güncelle
-- Aşağıdaki sorguyu çalıştır:
UPDATE orders 
SET 
    courier_id = 'ce598db8-4e36-4f0c-9fae-50f197162d87',
    updated_at = NOW()
WHERE id = '49ca4a0f-9e50-413a-bf72-f212485322a9';

-- 8) Doğrulama
SELECT 
    o.id,
    o.status,
    o.courier_id,
    ca.id AS assignment_id,
    ca.courier_id AS assignment_courier_id
FROM orders o
LEFT JOIN courier_assignments ca ON ca.order_id = o.id
WHERE o.id = '49ca4a0f-9e50-413a-bf72-f212485322a9';

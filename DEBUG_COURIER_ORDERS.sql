-- ============================================================================
-- KURYE PANELİ SORUNU DEBUG ET
-- ============================================================================

-- 1. Kurye profilini kontrol et (role = 'courier' olmalı)
SELECT id, full_name, role, is_online FROM profiles WHERE role = 'courier' LIMIT 5;

-- 2. Kuryesi olmayan dükkanları bul
SELECT id, name, has_own_courier, owner_id FROM shops WHERE has_own_courier = false LIMIT 10;

-- 3. Kuryesi olmayan dükkanlardaki siparişleri bul
SELECT 
    o.id,
    o.status,
    o.shop_id,
    s.name as shop_name,
    s.has_own_courier,
    o.created_at
FROM orders o
JOIN shops s ON o.shop_id = s.id
WHERE s.has_own_courier = false
AND o.status IN ('confirmed', 'preparing', 'ready')
ORDER BY o.created_at DESC
LIMIT 20;

-- 4. Mevcut orders SELECT policy'yi kontrol et
SELECT policyname, cmd, permissive FROM pg_policies 
WHERE tablename = 'orders' AND schemaname = 'public';

-- 5. Kurye atamalarını kontrol et
SELECT 
    ca.id,
    ca.order_id,
    ca.courier_id,
    ca.status,
    o.status as order_status
FROM courier_assignments ca
JOIN orders o ON ca.order_id = o.id
ORDER BY ca.assigned_at DESC
LIMIT 10;

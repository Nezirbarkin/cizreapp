-- ============================================================================
-- RPC FONKSİYONLARINI TEST ET
-- ============================================================================

-- 1. get_available_orders_for_courier fonksiyonunu test et
-- (Kurye ID'yi gerçek ID ile değiştirin)
SELECT * FROM get_available_orders_for_courier('KURYE_ID_BURAYA');

-- 2. get_courier_active_orders fonksiyonunu test et
SELECT * FROM get_courier_active_orders('KURYE_ID_BURAYA');

-- 3. Tüm siparişlerin durumlarını kontrol et
SELECT 
    o.id,
    o.status,
    s.name as shop_name,
    s.has_own_courier,
    EXISTS (
        SELECT 1 FROM courier_assignments ca 
        WHERE ca.order_id = o.id 
        AND ca.status IN ('assigned', 'picked_up', 'on_the_way', 'delivered')
    ) as has_courier
FROM orders o
JOIN shops s ON o.shop_id = s.id
ORDER BY o.created_at DESC
LIMIT 20;

-- 4. Tüm triggerları kontrol et
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers 
WHERE event_object_schema = 'public'
ORDER BY event_object_table;
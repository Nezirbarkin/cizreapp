-- Siparişlerin durumlarını kontrol et
SELECT 
    o.id,
    o.status,
    s.name as shop_name,
    s.has_own_courier,
    o.created_at
FROM orders o
JOIN shops s ON o.shop_id = s.id
WHERE s.has_own_courier = false
ORDER BY o.created_at DESC
LIMIT 30;
-- =============================================================================
-- KURYE SİPARİŞ GÖRÜNÜRLÜK DEBUG
-- Kurye paneli neden siparişi göremiyor? Hangi koşul sağlanmadı?
-- =============================================================================

-- 1) Son 10 sipariş ve durumları
SELECT
  id,
  shop_id,
  status,
  courier_id,
  total,
  created_at,
  updated_at
FROM orders
ORDER BY created_at DESC
LIMIT 10;

-- 2) Mağaza bazında has_own_courier durumu
SELECT
  id AS shop_id,
  name,
  has_own_courier,
  is_accepting_orders
FROM shops
ORDER BY updated_at DESC NULLS LAST
LIMIT 10;

-- 3) Kurye paneli mantığı: confirmed/preparing/ready VE has_own_courier=false olanlar
SELECT
  o.id AS order_id,
  o.status,
  o.created_at,
  s.name AS shop_name,
  s.has_own_courier
FROM orders o
JOIN shops s ON s.id = o.shop_id
WHERE o.status IN ('confirmed', 'preparing', 'ready')
  AND (s.has_own_courier IS NULL OR s.has_own_courier = false)
ORDER BY o.created_at DESC
LIMIT 20;

-- 4) Bu siparişlerden hangisi courier_assignments'a atanmış?
SELECT
  ca.order_id,
  ca.status AS assignment_status,
  ca.assigned_at,
  p.full_name AS courier_name
FROM courier_assignments ca
LEFT JOIN profiles p ON p.id = ca.courier_id
ORDER BY ca.assigned_at DESC NULLS LAST
LIMIT 20;

-- 5) orders tablosundaki status distinct değerleri
SELECT status, COUNT(*) AS cnt
FROM orders
GROUP BY status
ORDER BY cnt DESC;

-- 6) orders.courier_id dolu olanlar (eski sistem)
SELECT COUNT(*) AS orders_with_courier_id
FROM orders
WHERE courier_id IS NOT NULL;
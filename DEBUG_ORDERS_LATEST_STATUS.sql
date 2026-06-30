-- =============================================================================
-- SON 10 SİPARİŞİN TÜM ALANLARI (orders.courier_id yok, hata veren sorguyu düzelttik)
-- =============================================================================

-- 1) Son 10 siparişin detayı
SELECT
  id,
  shop_id,
  status,
  total,
  created_at,
  updated_at
FROM orders
ORDER BY created_at DESC
LIMIT 10;

-- 2) Hangi statülerde kaç sipariş var?
SELECT status, COUNT(*) AS cnt, MAX(created_at) AS latest
FROM orders
GROUP BY status
ORDER BY cnt DESC;

-- 3) Pending veya başka statüde takılı kalan sipariş var mı?
-- (Kurye panelinin gösterebilmesi için confirmed/preparing/ready olması gerekiyor)
SELECT
  o.id,
  o.status,
  o.created_at,
  o.updated_at,
  EXTRACT(EPOCH FROM (NOW() - o.updated_at)) AS seconds_since_update
FROM orders o
WHERE o.status NOT IN ('delivered', 'cancelled', 'on_the_way')
ORDER BY o.created_at DESC
LIMIT 20;
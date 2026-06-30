-- =============================================================================
-- SATICI DASHBOARD GENEL BAKIŞ DEBUG
-- Shops tablosundaki gelir/kazanç alanlarının gerçek değerlerini kontrol et
-- =============================================================================

-- 1) Aktif oturumdaki kullanıcı ID'si ile mağaza kaydı
SELECT
  id,
  name,
  owner_id,
  has_own_courier,
  cash_payment_revenue,
  online_payment_revenue,
  admin_credit,
  commission_debt,
  total_paid,
  total_collected_cash,
  commission_rate,
  delivery_fee,
  created_at,
  updated_at
FROM shops
ORDER BY updated_at DESC
LIMIT 5;

-- 2) Bu mağazaya ait teslim edilen sipariş sayısı ve toplam tutarı
SELECT
  s.id AS shop_id,
  s.name,
  s.cash_payment_revenue  AS shop_cash_revenue,
  s.online_payment_revenue AS shop_online_revenue,
  COUNT(o.id) FILTER (WHERE o.status NOT IN ('cancelled'))::int AS orders_total,
  COUNT(o.id) FILTER (WHERE o.status = 'delivered')::int        AS orders_delivered,
  COALESCE(SUM(o.subtotal) FILTER (WHERE o.status = 'delivered'), 0) AS orders_delivered_subtotal
FROM shops s
LEFT JOIN orders o ON o.shop_id = s.id
GROUP BY s.id, s.name, s.cash_payment_revenue, s.online_payment_revenue
ORDER BY s.updated_at DESC
LIMIT 5;

-- 3) Mağazanın shop_id'sini öğrendikten sonra, doğrudan o mağaza için siparişler
-- (Sen shop_id'yi yukarıdaki sonuçtan alıp aşağıya yaz):
-- SELECT id, status, subtotal, payment_method, created_at
-- FROM orders
-- WHERE shop_id = 'SHOP_ID_BURAYA'
-- ORDER BY created_at DESC
-- LIMIT 20;

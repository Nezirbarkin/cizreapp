-- ============================================================================
-- DEĞERLENDİRME SORUNUNU DEBUG ET
-- ============================================================================

-- 1. get_pending_reviews RPC fonksiyonunu test et
-- (Kullanıcı ID'yi gerçek kullanıcı ID'nizle değiştirin)
SELECT * FROM get_pending_reviews('KULLANICI_ID_BURAYA');

-- 2. can_review_order RPC fonksiyonunu test et
-- (Parametreleri gerçek değerlerle değiştirin)
SELECT can_review_order(
    'KULLANICI_ID_BURAYA',
    'SHOP_ID_BURAYA',
    'SIPARIS_ID_BURAYA'
);

-- 3. Teslim edilmiş siparişleri listele
SELECT 
    id, 
    status, 
    user_id, 
    shop_id, 
    delivered_at,
    created_at
FROM orders
WHERE status = 'delivered'
ORDER BY delivered_at DESC
LIMIT 10;

-- 4. Sipariş için zaten değerlendirme yapılmış mı kontrol et
SELECT 
    r.id,
    r.shop_id,
    r.order_id,
    r.rating
FROM shop_reviews r
WHERE r.order_id = 'SIPARIS_ID_BURAYA';

-- 5. product_reviews tablosunda kontrol et
SELECT * FROM product_reviews WHERE order_id = 'SIPARIS_ID_BURAYA';

-- 6. RPC fonksiyonlarının tanımlarını kontrol et
SELECT routine_name, routine_definition
FROM information_schema.routines
WHERE routine_name IN ('get_pending_reviews', 'can_review_order')
AND routine_schema = 'public';
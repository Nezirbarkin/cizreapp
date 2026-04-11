-- ============================================================================
-- KOMİSYON SİSTEMİNİ DEBUG ET
-- ============================================================================

-- 1. Orders tablosundaki komisyon trigger'larını gör
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'orders'
  AND (trigger_name LIKE '%commission%' 
       OR trigger_name LIKE '%shop_balance%'
       OR trigger_name LIKE '%calculate_order%')
ORDER BY trigger_name;

-- 2. Mevcut calculate_order_commission fonksiyonunu gör
SELECT 
    routine_name,
    routine_definition
FROM information_schema.routines
WHERE routine_name = 'calculate_order_commission';

-- 3. Mevcut update_shop_balance fonksiyonunu gör
SELECT 
    routine_name,
    routine_definition
FROM information_schema.routines
WHERE routine_name = 'update_shop_balance';

-- 4. Örnek sipariş kaydı kontrolü (kuryesi olan satıcı + card_on_delivery)
SELECT 
    id,
    order_number,
    shop_id,
    payment_method,
    status,
    total,
    subtotal,
    delivery_fee,
    admin_commission,
    seller_cash_collected,
    seller_debt_amount,
    seller_credit_amount,
    seller_net_amount,
    commission_status,
    seller_has_own_courier,
    created_at
FROM orders
WHERE payment_method = 'card_on_delivery'
  AND status = 'delivered'
ORDER BY created_at DESC
LIMIT 5;

-- 5. Shops tablosundaki ilgili dükkanın durumu
SELECT 
    s.id,
    s.name,
    s.has_own_courier,
    s.admin_credit,
    s.commission_debt,
    s.total_collected_cash,
    s.cash_payment_revenue,
    s.online_payment_revenue
FROM shops s
WHERE s.has_own_courier = true;

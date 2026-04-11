-- Trigger'ın doğru çalışıp çalışmadığını test et
-- Test siparişi oluştur ve sonucu gör

-- 1. Önce mevcut trigger fonksiyonunu kontrol et
SELECT 
    routine_name,
    LEFT(routine_definition, 500) as definition_preview
FROM information_schema.routines
WHERE routine_name IN ('calculate_order_commission', 'update_shop_balance');

-- 2. Test için yeni sipariş ekle (manual)
-- Bu kodu çalıştırmayın, sadece örnek
-- INSERT INTO orders (
--   order_number, user_id, shop_id, payment_method, subtotal, delivery_fee, total, status
-- ) VALUES (
--   'TEST' || extract(epoch from now())::bigint,
--   (SELECT id FROM profiles WHERE is_seller = true LIMIT 1),
--   'bb4a4d6f-cba4-474d-b409-90afcaedd0f5', -- CizreApp shop_id
--   'card_on_delivery',
--   100, 15, 115,
--   'pending'
-- );

-- 3. Son eklenen siparişin komisyon hesaplamalarını kontrol et
SELECT 
    id,
    order_number,
    payment_method,
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
    status,
    created_at
FROM orders
WHERE shop_id = 'bb4a4d6f-cba4-474d-b409-90afcaedd0f5'
ORDER BY created_at DESC
LIMIT 1;

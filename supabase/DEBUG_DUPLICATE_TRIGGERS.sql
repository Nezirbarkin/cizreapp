-- SORUN TESPİTİ: Çift trigger problemi!
-- Sistem hem eski hem yeni commission trigger'larını çalıştırıyor

-- 1. Tüm orders ve payout_requests trigger'larını listele
SELECT 
  t.tgname as trigger_name,
  c.relname as table_name,
  p.proname as function_name,
  CASE t.tgtype::integer & 66
    WHEN 2 THEN 'BEFORE'
    WHEN 64 THEN 'INSTEAD OF'
    ELSE 'AFTER'
  END as timing,
  t.tgenabled as enabled,
  pg_get_triggerdef(t.oid) as full_definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE c.relname IN ('orders', 'payout_requests')
  AND NOT t.tgisinternal
ORDER BY c.relname, t.tgname;

-- 2. Çakışan function'ları kontrol et
SELECT 
  p.proname as function_name,
  n.nspname as schema_name,
  pg_get_functiondef(p.oid) as definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname IN (
  'calculate_order_commission',
  'auto_calculate_commission',
  'update_shop_balance',
  'validate_payout_request',
  'clear_shop_balance'
)
ORDER BY p.proname;

-- 3. Kuryesi olmayan satıcıların mevcut durumu
SELECT 
  id,
  name,
  has_own_courier,
  commission_debt,
  admin_credit,
  (admin_credit - commission_debt) as net_amount
FROM shops
WHERE has_own_courier = FALSE OR has_own_courier IS NULL
ORDER BY created_at DESC
LIMIT 5;

-- 4. Son oluşturulan siparişlerin komisyon bilgileri
SELECT 
  o.id,
  s.name as shop_name,
  s.has_own_courier,
  o.payment_method,
  o.subtotal,
  o.delivery_fee,
  o.total,
  o.admin_commission,
  o.seller_debt_amount,
  o.seller_credit_amount,
  o.commission_status,
  o.created_at
FROM orders o
JOIN shops s ON s.id = o.shop_id
ORDER BY o.created_at DESC
LIMIT 10;

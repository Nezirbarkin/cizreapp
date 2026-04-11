-- Komisyon sistemi debug script
-- Bu script'i çalıştırarak mevcut durumu kontrol edebilirsin

-- 1. Kuryesi olmayan satıcıların durumu
SELECT 
  id,
  name,
  has_own_courier,
  commission_debt,
  admin_credit,
  (admin_credit - commission_debt) as net_receivable
FROM shops 
WHERE has_own_courier = FALSE OR has_own_courier IS NULL
ORDER BY created_at DESC;

-- 2. Kuryesi olan satıcıların durumu
SELECT 
  id,
  name,
  has_own_courier,
  commission_debt,
  admin_credit,
  (admin_credit - commission_debt) as net_receivable
FROM shops 
WHERE has_own_courier = TRUE
ORDER BY created_at DESC;

-- 3. Son siparişlerin komisyon bilgileri
SELECT 
  o.id,
  o.shop_id,
  s.name as shop_name,
  o.payment_method,
  o.seller_has_own_courier,
  o.subtotal,
  o.delivery_fee,
  o.total,
  o.admin_commission,
  o.seller_debt_amount,
  o.seller_credit_amount,
  o.commission_status
FROM orders o
JOIN shops s ON s.id = o.shop_id
ORDER BY o.created_at DESC
LIMIT 20;

-- 4. Trigger function'ların search_path ayarlarını kontrol et
SELECT 
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_functiondef(p.oid) as definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN (
    'calculate_order_commission',
    'update_shop_balance',
    'validate_payout_request',
    'clear_shop_balance'
  );

-- 5. Aktif trigger'ları listele
SELECT 
  t.tgname as trigger_name,
  c.relname as table_name,
  p.proname as function_name,
  CASE t.tgtype::integer & 1
    WHEN 1 THEN 'ROW'
    ELSE 'STATEMENT'
  END as level,
  CASE t.tgtype::integer & 66
    WHEN 2 THEN 'BEFORE'
    WHEN 64 THEN 'INSTEAD OF'
    ELSE 'AFTER'
  END as timing,
  CASE t.tgtype::integer & 28
    WHEN 4 THEN 'INSERT'
    WHEN 8 THEN 'DELETE'
    WHEN 16 THEN 'UPDATE'
    WHEN 20 THEN 'INSERT OR UPDATE'
    WHEN 24 THEN 'DELETE OR UPDATE'
    WHEN 28 THEN 'INSERT OR UPDATE OR DELETE'
  END as event
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE c.relname IN ('orders', 'payout_requests')
  AND t.tgname LIKE '%commission%' OR t.tgname LIKE '%balance%'
ORDER BY c.relname, t.tgname;

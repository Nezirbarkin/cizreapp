-- Test Kupon Verileri
-- Satıcılar için örnek kuponlar

-- Dükkan 1 için test kuponları
INSERT INTO shop_coupons (shop_id, code, title, description, discount_type, discount_value, minimum_order_amount, usage_limit, usage_per_user, is_active) 
SELECT 
  id,
  'HOŞGELDİN10',
  'İlk Sipariş İndirimi',
  'İlk siparişinizde %10 indirim kazanın!',
  'percentage',
  10.0,
  0,
  NULL,
  1,
  true
FROM shops 
LIMIT 1;

INSERT INTO shop_coupons (shop_id, code, title, description, discount_type, discount_value, minimum_order_amount, usage_limit, usage_per_user, is_active) 
SELECT 
  id,
  'YENİ100',
  '100 TL İndirim',
  '100 TL ve üzeri alışverişlerde 100 TL indirim',
  'fixed_amount',
  100.0,
  100.0,
  NULL,
  1,
  true
FROM shops 
LIMIT 1;

INSERT INTO shop_coupons (shop_id, code, title, description, discount_type, discount_value, minimum_order_amount, usage_limit, usage_per_user, is_active) 
SELECT 
  id,
  'BEDAVA50',
  '50 TL Ücretsiz Kargo',
  '50 TL üzeri siparişlerde kargo bedava!',
  'fixed_amount',
  15.0,
  50.0,
  NULL,
  3,
  true
FROM shops 
LIMIT 1;

-- Diğer dükkanlar için de kupon ekle
INSERT INTO shop_coupons (shop_id, code, title, description, discount_type, discount_value, minimum_order_amount, usage_limit, usage_per_user, is_active)
SELECT 
  id,
  'İNDİRİM20',
  '%20 İndirim Fırsatı',
  'Siparişinizde %20 indirim!',
  'percentage',
  20.0,
  0,
  NULL,
  1,
  true
FROM shops 
OFFSET 1
LIMIT 1;

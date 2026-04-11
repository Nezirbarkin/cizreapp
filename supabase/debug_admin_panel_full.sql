-- Admin Panelinde Ürün/Kazanç Görünme Sorunu İÇİN DİAGNOSTİK SQL
-- =====================================================

-- Bu sorguyu Supabase SQL Editor'da sırayla çalıştırın
-- Sonuçları analiz ederek sorunu bulun

-- =====================================================
-- 1. ORDERS TABLOSU YAPISI - ÖNCE BUNU KONTROL ET
-- =====================================================
SELECT column_name, data_type, column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'orders' 
ORDER BY ordinal_position;

-- =====================================================
-- 2. SHOPS TABLOSU YAPISI
-- =====================================================
SELECT 
  s.id,
  s.name,
  s.admin_credit,
  s.commission_debt
FROM shops s
ORDER BY s.name;

-- =====================================================
-- 3. PRODUCTS TABLOSU - shop_id KONTROLÜ
-- =====================================================
-- Her dükkan için kaç ürün var?
SELECT 
  p.shop_id,
  COUNT(*) as product_count
FROM products p
GROUP BY p.shop_id
ORDER BY product_count DESC;

-- =====================================================
-- 4. PRODUCTS TABLOSU - DETAYLI
-- =====================================================
-- İlk 5 dükkan ve ürünleri
SELECT 
  s.name as shop_name,
  s.id as shop_id,
  p.id as product_id,
  p.name as product_name,
  p.is_active as product_is_active,
  p.stock_quantity as product_stock
FROM shops s
LEFT JOIN products p ON p.shop_id = s.id
WHERE s.id IN (
  SELECT id FROM shops ORDER BY name LIMIT 5
)
ORDER BY s.name, p.name
LIMIT 50;

-- =====================================================
-- 5. ORDERS - Her dükkan için sipariş sayısı ve gelir
-- =====================================================
SELECT 
  s.name as shop_name,
  COUNT(*) FILTER (WHERE o.status = 'delivered') as delivered_orders,
  SUM(o.total) FILTER (WHERE o.status = 'delivered') as total_revenue,
  SUM(o.commission_amount) FILTER (WHERE o.status = 'delivered') as total_commission
FROM shops s
LEFT JOIN orders o ON o.shop_id = s.id
GROUP BY s.id, s.name
ORDER BY s.name;

-- =====================================================
-- 6. MEVCUT PRODUCTS SELECT POLICY'LERİ
-- =====================================================
SELECT 
  pol.polname AS policy_name,
  pol.polcmd AS command,
  pg_get_expr(pol.polqual, pol.polrelid) AS using_expr
FROM pg_policy pol
WHERE pol.polrelid = 'public.products'::regclass;

-- =====================================================
-- 7. MEVCUT ORDERS SELECT POLICY'LERİ
-- =====================================================
SELECT 
  pol.polname AS policy_name,
  pol.polcmd AS command,
  pg_get_expr(pol.polqual, pol.polrelid) AS using_expr
FROM pg_policy pol
WHERE pol.polrelid = 'public.orders'::regclass;

-- =====================================================
-- 8. MEVCUT SHOPS SÜTUNLARI VE DEĞERLER
-- =====================================================
SELECT 
  id,
  name,
  admin_credit,
  commission_debt,
  cash_payment_revenue,
  online_payment_revenue,
  total_collected_cash,
  total_paid
FROM shops
LIMIT 10;

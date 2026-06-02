-- ============================================
-- MEVCUT RLS POLİTİKALARINI KONTROL ET
-- Supabase SQL Editor'de çalıştırın
-- ============================================

-- Orders tablosu politikaları
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'orders'
  AND schemaname = 'public'
ORDER BY policyname, cmd;

-- Shops tablosu politikaları
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'shops'
  AND schemaname = 'public'
ORDER BY policyname, cmd;

-- Courier_assignments tablosu politikaları
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'courier_assignments'
  AND schemaname = 'public'
ORDER BY policyname, cmd;

-- Notifications tablosu politikaları  
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'notifications'
  AND schemaname = 'public'
ORDER BY policyname, cmd;

-- Kuryesi olmayan dükkan var mı?
SELECT id, name, has_own_courier 
FROM shops 
WHERE has_own_courier IS DISTINCT FROM true
LIMIT 20;

-- Sipariş durumları
SELECT status, count(*) as count
FROM orders
GROUP BY status
ORDER BY count DESC;

-- Kurye rolü olan kullanıcılar
SELECT id, role, full_name, fcm_token, is_online
FROM profiles 
WHERE role = 'courier'
LIMIT 10;

-- Kuryesi olmayan satıcıların confirmed/preparing/ready siparişleri
SELECT 
  o.id,
  o.status,
  o.total,
  o.shop_id,
  o.created_at,
  s.name as shop_name,
  s.has_own_courier,
  EXISTS(SELECT 1 FROM courier_assignments ca WHERE ca.order_id = o.id AND ca.status IN ('assigned', 'picked_up')) as has_assignment
FROM orders o
JOIN shops s ON o.shop_id = s.id
WHERE o.status IN ('confirmed', 'preparing', 'ready')
  AND s.has_own_courier IS DISTINCT FROM true
ORDER BY o.created_at DESC
LIMIT 20;
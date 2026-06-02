-- ============================================
-- KURYE SİPARİŞ SORUNU - DEBUG SQL
-- Bu sorguları Supabase SQL Editor'de çalıştırın
-- ============================================

-- 1. Kuryesi olmayan satıcıları kontrol et
SELECT id, name, has_own_courier 
FROM shops 
WHERE has_own_courier IS DISTINCT FROM true
LIMIT 20;

-- 2. Mevcut kurye rollerini kontrol et
SELECT id, role, full_name, username
FROM profiles 
WHERE role = 'courier'
LIMIT 10;

-- 3. Confirmed, preparing veya ready durumundaki siparişleri kontrol et
SELECT 
  o.id,
  o.status,
  o.total,
  o.shop_id,
  s.name as shop_name,
  s.has_own_courier
FROM orders o
JOIN shops s ON o.shop_id = s.id
WHERE o.status IN ('confirmed', 'preparing', 'ready')
  AND s.has_own_courier IS DISTINCT FROM true
ORDER BY o.created_at DESC
LIMIT 50;

-- 4. Tüm siparişlerin durumlarını say
SELECT status, count(*) as count
FROM orders
GROUP BY status
ORDER BY count DESC;

-- 5. Kurye atamalarını kontrol et
SELECT 
  ca.id,
  ca.order_id,
  ca.courier_id,
  ca.status as assignment_status,
  o.status as order_status
FROM courier_assignments ca
JOIN orders o ON ca.order_id = o.id
ORDER BY ca.assigned_at DESC
LIMIT 20;

-- 6. Son kurye bildirimlerini kontrol et
SELECT 
  id,
  user_id,
  type,
  title,
  content,
  created_at
FROM notifications
WHERE type LIKE 'courier%'
ORDER BY created_at DESC
LIMIT 20;

-- 7. Kurye profilinde FCM token var mı kontrol et
SELECT id, role, fcm_token, is_online
FROM profiles 
WHERE role = 'courier'
LIMIT 10;

-- 8. RLS durumunu kontrol et
SELECT 
    c.relname as table_name,
    CASE WHEN c.relrowsecurity THEN 'ENABLED' ELSE 'DISABLED' END as rls_status
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE c.relname IN ('orders', 'shops', 'courier_assignments', 'notifications')
AND n.nspname = 'public';

-- 9. Orders tablosu RLS politikalarını listele
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
ORDER BY cmd;

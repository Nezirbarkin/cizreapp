-- Orders tablosundaki TÜM politikaları kontrol et
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'orders'
  AND schemaname = 'public'
ORDER BY policyname, cmd;

-- Kurye rolünde kullanıcı var mı?
SELECT id, role, full_name, fcm_token, is_online, username
FROM profiles 
WHERE role = 'courier'
LIMIT 10;

-- Tüm kullanıcı rollerini say
SELECT role, count(*) as count
FROM profiles
GROUP BY role
ORDER BY count DESC;

-- Son 10 siparişin durumlarını kontrol et
SELECT id, status, shop_id, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 10;

-- Kurye bildirimleri var mı?
SELECT count(*) as count FROM notifications WHERE type LIKE 'courier%';
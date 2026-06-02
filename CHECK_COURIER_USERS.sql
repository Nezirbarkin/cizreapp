-- Kurye rolü olan kullanıcıları kontrol et
SELECT id, role, full_name, fcm_token, is_online, username
FROM profiles 
WHERE role = 'courier'
LIMIT 10;

-- Eğer kurye yoksa, mevcut kullanıcıların rollerini göster
SELECT id, role, full_name, username
FROM profiles 
ORDER BY created_at DESC
LIMIT 20;

-- Notifications tablosunda kurye bildirimi var mı?
SELECT id, user_id, type, title, content, is_read, created_at
FROM notifications
WHERE type LIKE 'courier%'
ORDER BY created_at DESC
LIMIT 20;

-- RLS politikalarını kontrol et - kurye için
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'orders'
  AND schemaname = 'public'
  AND policyname LIKE '%ourier%'
ORDER BY policyname;

-- Shops tablosundaki tüm politikaları kontrol et
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'shops'
  AND schemaname = 'public'
ORDER BY policyname;
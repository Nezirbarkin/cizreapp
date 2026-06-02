-- ============================================
-- BİLDİRİM SİSTEMİ DEBUG
-- ============================================

-- 1. Notifications tablosundaki tüm kurye bildirimlerini göster
SELECT id, user_id, type, title, left(content, 50) as content_preview, is_read, created_at
FROM notifications
WHERE type LIKE 'courier%'
ORDER BY created_at DESC
LIMIT 20;

-- 2. Tüm bildirim tiplerini say
SELECT type, count(*) as count
FROM notifications
GROUP BY type
ORDER BY count DESC;

-- 3. Notifications tablosu RLS politikalarını kontrol et
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'notifications'
  AND schemaname = 'public'
ORDER BY policyname, cmd;

-- 4. Kurye test4 kullanıcısının bildirimlerini kontrol et
SELECT id, type, title, left(content, 50) as content_preview, is_read, created_at
FROM notifications
WHERE user_id = 'ce598db8-4e36-4f0c-9fae-50f197162d87'
ORDER BY created_at DESC
LIMIT 20;

-- 5. Son siparişin detaylarını kontrol et (shop_id ile)
SELECT o.id, o.status, o.shop_id, s.name as shop_name, s.has_own_courier
FROM orders o
JOIN shops s ON o.shop_id = s.id
WHERE o.id = 'ae8c1262-9b90-48d2-b919-94e6bd7710e4';

-- 6. courier_assignments INSERT politikasını kontrol et
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'courier_assignments'
  AND schemaname = 'public'
ORDER BY policyname, cmd;
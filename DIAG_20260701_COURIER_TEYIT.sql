-- =============================================================================
-- DIAG_20260701_COURIER_TEYIT.sql
-- "Teslim ettim → sipariş kurye panelinde kayboluyor" kök neden teyidi
-- + Kurye/orders RLS ve tetikleyici kontrolleri
-- Sonuçları kopyala-yapıştır olarak Claude'a gönder.
-- =============================================================================

-- [1] orders üzerindeki TÜM SELECT policy'leri
-- Kuryenin orders'ı görüp göremediğini teyit eder (en kritik kontrol).
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'orders'
ORDER BY cmd, policyname;

-- [2] orders.delivered_courier_* sütunlarının varlığı
-- _completeDelivery bu sütunlara yazıyor; yoksa update sessizce fallback'e düşüyor.
SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'delivered_courier_id'
  ) THEN 'EXISTS' ELSE 'MISSING' END AS delivered_courier_id,
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'delivered_courier_name'
  ) THEN 'EXISTS' ELSE 'MISSING' END AS delivered_courier_name,
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'delivered_courier_phone'
  ) THEN 'EXISTS' ELSE 'MISSING' END AS delivered_courier_phone,
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'delivered_at'
  ) THEN 'EXISTS' ELSE 'MISSING' END AS delivered_at;

-- [3] orders üzerindeki TETİKLEYİCİLER (create_seller_earnings_on_delivery tetikleniyor mu?)
SELECT
  t.trigger_name,
  t.event_manipulation,
  t.action_timing,
  p.proname AS function_name
FROM information_schema.triggers t
JOIN pg_proc p ON p.oid = (
  SELECT t.tfunctionoid FROM pg_trigger tr WHERE tr.tgname = t.trigger_name LIMIT 1
)
WHERE t.event_object_schema = 'public' AND t.event_object_table = 'orders'
ORDER BY t.trigger_name;

-- [4] SON 5 DELIVERED SİPARİŞ — kurye_assignments hâlâ görünür mü?
-- Test: Teslim edilen sipariş courier_assignments'ında görünüyor mu? (RLS teyidi)
SELECT
  o.id AS order_id,
  o.status AS order_status,
  o.delivered_at,
  o.delivered_courier_id,
  ca.id AS assignment_id,
  ca.courier_id,
  ca.status AS assignment_status,
  ca.delivered_at AS ca_delivered_at,
  p.role AS courier_role
FROM orders o
LEFT JOIN courier_assignments ca ON ca.order_id = o.id
LEFT JOIN profiles p ON p.id = ca.courier_id
WHERE o.status = 'delivered'
ORDER BY o.delivered_at DESC NULLS LAST
LIMIT 5;

-- [5] CUP kurye örneği için: courier_assignments SELECT policy'leri
SELECT policyname, cmd, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'courier_assignments'
ORDER BY cmd, policyname;

-- [6] notifications tip CHECK constraint — kuryeye giden tüm tipleri içeriyor mu?
SELECT pg_get_constraintdef(c.oid) AS constraint_def
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
WHERE t.relname = 'notifications' AND c.conname LIKE '%type%check%';

-- [7] notifications_push_trigger aktif mi?
SELECT trigger_name, event_manipulation, action_timing, action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'notifications'
  AND trigger_name = 'notifications_push_trigger';

-- [8] send_push_on_notification fonksiyonunun varlığı ve aramayı test et
SELECT proname, prosecdef AS is_security_definer
FROM pg_proc
WHERE proname IN (
  'send_push_on_notification',
  'create_seller_earnings_on_delivery',
  'update_order_on_courier_assignment',
  'update_order_status_on_courier_delivery'
);

-- =============================================================================
-- Beklenen normal durum:
--   [1] kurye için bir SELECT policy olmalı (EXISTS courier_assignments koşulu ile)
--   [2] delivered_courier_id/name/phone hepsi EXISTS
--   [3] orders üzerinde AFTER UPDATE veya AFTER INSERT trigger'ları (komisyon vs.)
--   [4] delivered sipariş + courier_assignments satırı GÖRÜNÜR olmalı (RLS kapsamı)
--   [5] kurye kendi assignment'larını görebilmeli, admin/satıcı da kendininkileri
--   [6] notifications.type CHECK'i courier_new_order/ready/assigned vb. tipleri içermeli
--   [7] notifications_push_trigger var ve AFTER INSERT olmalı
--   [8] send_push_on_notification fonksiyonu SECURITY DEFINER olmalı
-- Anomali durumda (örn. [4] delivered olmasına rağmen assignment görünmüyor)
-- kök neden RLS veya tetikleyici hatasıdır.
-- =============================================================================

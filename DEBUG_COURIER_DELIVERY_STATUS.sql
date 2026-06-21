-- ============================================================================
-- Kurye Teslim ve Değerlendirme Sorunlarını Debug Etmek İçin SQL Sorguları
-- ============================================================================

-- 1. Son teslim edilen siparişlerin durumunu kontrol et
SELECT 
    o.id,
    o.status,
    o.created_at,
    o.delivered_at,
    ca.status as courier_assignment_status,
    ca.courier_id,
    p.full_name as courier_name
FROM orders o
LEFT JOIN courier_assignments ca ON o.id = ca.order_id
LEFT JOIN profiles p ON ca.courier_id = p.id
WHERE o.status = 'delivered' OR ca.status = 'delivered'
ORDER BY o.updated_at DESC
LIMIT 20;

-- 2. notifications tablosunda pending_review tipinde bildirimler var mı?
SELECT 
    id,
    user_id,
    type,
    title,
    content,
    created_at,
    is_read
FROM notifications
WHERE type = 'pending_review'
ORDER BY created_at DESC
LIMIT 20;

-- 3. Bildirim tiplerini kontrol et
SELECT DISTINCT type FROM notifications ORDER BY type;

-- 4. Kurye atamalarının durumlarını kontrol et
SELECT 
    ca.id,
    ca.order_id,
    ca.status,
    ca.courier_id,
    ca.assigned_at,
    ca.delivered_at,
    o.status as order_status
FROM courier_assignments ca
JOIN orders o ON ca.order_id = o.id
WHERE ca.status = 'delivered'
ORDER BY ca.delivered_at DESC
LIMIT 20;

-- 5. Bir siparişin tüm sürecini takip et
-- (Sipariş ID'yi kendi siparişinizle değiştirin)
SELECT 
    o.id,
    o.status,
    o.created_at,
    ca.status as courier_status,
    ca.assigned_at,
    ca.picked_up_at,
    ca.delivered_at
FROM orders o
LEFT JOIN courier_assignments ca ON o.id = ca.order_id
WHERE o.id = 'SİPARİŞ_ID_BURAYA'
ORDER BY o.created_at DESC;

-- 6. Bildirim triggersını kontrol et
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers 
WHERE event_object_schema = 'public' 
AND event_object_table = 'notifications'
ORDER BY trigger_name;

-- 7. reviews tablosunda son değerlendirmeleri kontrol et
SELECT 
    r.id,
    r.order_id,
    r.rating,
    r.review_text,
    r.created_at,
    o.status as order_status
FROM reviews r
JOIN orders o ON r.order_id = o.id
ORDER BY r.created_at DESC
LIMIT 20;

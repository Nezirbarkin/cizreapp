-- ============================================================================
-- Bildirim Türlerini ve Sorunu Analiz Et
-- ============================================================================

-- 1. Mevcut notification tiplerini gör
SELECT DISTINCT type, COUNT(*) as count
FROM notifications
GROUP BY type
ORDER BY type;

-- 2. Mevcut constraint'i gör
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conname = 'notifications_type_check';

-- 3. pending_review tipinde kaç satır var?
SELECT COUNT(*) as pending_review_count
FROM notifications
WHERE type = 'pending_review';

-- 4. Tüm unique tipleri listele
SELECT DISTINCT unnest(string_to_array(
    (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'notifications_type_check'),
    ','
)) as allowed_type;

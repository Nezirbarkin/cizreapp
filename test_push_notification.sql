-- ============================================
-- PUSH NOTIFICATION TEST SQL
-- Supabase SQL Editor'da çalıştırın
-- ============================================

-- NOT: Kendi user_id'nizi kullanın (örn: bb8b8823-656d-436d-9f49-c28f312d0a32)

-- 1. Önce FCM token kontrolü
SELECT 
    id,
    username,
    CASE 
        WHEN fcm_token IS NULL THEN 'YOK ❌'
        ELSE CONCAT('VAR ✅ (', LEFT(fcm_token, 30), '...)')
    END as fcm_status
FROM profiles 
WHERE id = 'bb8b8823-656d-436d-9f49-c28f312d0a32'; -- Kendi user_id'nizi buraya yazın

-- 2. Test bildirimi oluştur
-- (Bu INSERT trigger'ı tetiklemeli ve Edge Function çağırmalı)
INSERT INTO notifications (user_id, type, title, content, is_read)
VALUES (
    'bb8b8823-656d-436d-9f49-c28f312d0a32', -- Kendi user_id'nizi buraya yazın
    'like',
    '🧪 Test Push Bildirimi',
    'Bu bir test bildirimidir - ' || now(),
    false
)
RETURNING id, user_id, type, title, created_at;

-- 3. Bildirim oluşturuldu mu kontrol et
SELECT 
    id,
    type,
    title,
    created_at
FROM notifications 
WHERE user_id = 'bb8b8823-656d-436d-9f49-c28f312d0a32' -- Kendi user_id'nizi buraya yazın
ORDER BY created_at DESC 
LIMIT 5;

-- 4. Database log kontrolü (PostgreSQL logs)
-- Bu sorgu çalışmazsa, Edge Function log kontrol edin
-- SELECT * FROM pg_stat_statements WHERE query LIKE '%http_post%';

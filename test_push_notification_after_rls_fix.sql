-- ============================================================
-- PUSH NOTIFICATION TEST - RLS FIX SONRASI
-- Kullanıcı ID: 70ab05f6-6aeb-4d32-810e-f3955c300f12
-- ============================================================

-- 1. Önce FCM token'ınızı kontrol edelim
SELECT id, username, fcm_token 
FROM profiles 
WHERE id = '70ab05f6-6aeb-4d32-810e-f3955c300f12';

-- 2. Kendinize test bildirimi gönderin
-- Bu INSERT trigger'ı tetikleyecek → Edge Function → FCM → Cihazınıza bildirim
INSERT INTO notifications (
    user_id,
    type,
    actor_id,
    created_at
) VALUES (
    '70ab05f6-6aeb-4d32-810e-f3955c300f12',
    'like',
    '70ab05f6-6aeb-4d32-810e-f3955c300f12',
    NOW()
)
RETURNING id, type, created_at;

-- 3. Bildirimin kaydedildiğini doğrulayın
SELECT id, type, actor_id, is_read, created_at 
FROM notifications 
WHERE user_id = '70ab05f6-6aeb-4d32-810e-f3955c300f12' 
ORDER BY created_at DESC 
LIMIT 5;

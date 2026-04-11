-- ============================================================
-- MANUEL INSERT TEST - DASHBOARD'DAN DENE
-- ============================================================
-- Eğer bu INSERT başarılı olursa, policy doğrudur ve problem app tarafında.
-- Eğer bu da başarısız olursa, policy veya RLS'de problem var.

-- Authenticated user olarak INSERT test
INSERT INTO notifications (
    user_id,
    type,
    actor_id,
    created_at
) VALUES (
    '78665f8b-6a07-40f3-b13d-d4b5a29296c6',  -- Sizin user_id
    'like',
    '78665f8b-6a07-40f3-b13d-d4b5a29296c6',  -- Sizin user_id
    NOW()
)
RETURNING *;

-- Eğer yukarıdaki başarılı olursa, policy çalışıyordur.
-- Şimdi auth.uid() kontrolü yapalım:
SELECT 
    auth.uid() as current_user_id,
    auth.role() as current_role;

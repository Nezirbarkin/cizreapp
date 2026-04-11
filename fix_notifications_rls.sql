-- ============================================
-- NOTIFICATIONS RLS POLICY FIX
-- Bildirim oluşturma hatası çözümü
-- ============================================

-- Sorun: "new row violates row-level security policy for table notifications"
-- Çözüm: Insert policy ekle veya güncelle

-- 1. Mevcut policies kontrol et
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'notifications';

-- 2. Eski INSERT policy'yi sil (varsa)
DROP POLICY IF EXISTS "Users can insert their own notifications" ON notifications;
DROP POLICY IF EXISTS "Allow insert notifications" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_policy" ON notifications;

-- 3. YENİ INSERT POLICY - Authenticated kullanıcılar bildirim oluşturabilir
CREATE POLICY "notifications_insert_policy"
ON notifications
FOR INSERT
TO authenticated
WITH CHECK (true); -- Herkes kendi user_id'sine bildirim oluşturabilir

-- 4. SELECT policy (okuma izni)
DROP POLICY IF EXISTS "notifications_select_policy" ON notifications;
CREATE POLICY "notifications_select_policy"
ON notifications
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR auth.uid() IN (
  SELECT id FROM profiles WHERE role = 'admin'
));

-- 5. UPDATE policy (güncelleme izni - is_read için)
DROP POLICY IF EXISTS "notifications_update_policy" ON notifications;
CREATE POLICY "notifications_update_policy"
ON notifications
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 6. DELETE policy
DROP POLICY IF EXISTS "notifications_delete_policy" ON notifications;
CREATE POLICY "notifications_delete_policy"
ON notifications
FOR DELETE
TO authenticated
USING (user_id = auth.uid() OR auth.uid() IN (
  SELECT id FROM profiles WHERE role = 'admin'
));

-- 7. RLS enable kontrol
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- 8. Doğrulama - yeni policies
SELECT 
    policyname,
    cmd,
    roles
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY cmd;

-- ============================================================
-- NOTIFICATIONS TABLOSU DÜZELTMELERİ
-- ============================================================

-- 1. Title kolonuna DEFAULT value ekle (trigger'dan gelen bildirimler için)
ALTER TABLE notifications 
ALTER COLUMN title SET DEFAULT '',
ALTER COLUMN content SET DEFAULT '';

-- 2. Tüm mevcut policy'leri kaldır ve yeniden oluştur
DROP POLICY IF EXISTS notifications_insert_policy ON notifications;
DROP POLICY IF EXISTS notifications_select_policy ON notifications;
DROP POLICY IF EXISTS notifications_update_policy ON notifications;
DROP POLICY IF EXISTS notifications_delete_policy ON notifications;

-- 3. INSERT Policy - HER authenticated kullanıcı bildirim oluşturabilir
CREATE POLICY notifications_insert_policy ON notifications
FOR INSERT
TO authenticated
WITH CHECK (true);

-- 4. SELECT Policy - Kullanıcı sadece kendi bildirimlerini görebilir
CREATE POLICY notifications_select_policy ON notifications
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
));

-- 5. UPDATE Policy - Kullanıcı sadece kendi bildirimlerini güncelleyebilir
CREATE POLICY notifications_update_policy ON notifications
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 6. DELETE Policy - Kullanıcı kendi veya admin silme yapabilir
CREATE POLICY notifications_delete_policy ON notifications
FOR DELETE
TO authenticated
USING (user_id = auth.uid() OR EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
));

-- 7. Politikaların doğruluğunu kontrol et
SELECT 
    policyname,
    cmd,
    permissive,
    with_check,
    qual
FROM pg_policies 
WHERE tablename = 'notifications';

-- 8. Test INSERT (title DEFAULT kullanacak)
INSERT INTO notifications (user_id, type, actor_id)
VALUES ('70ab05f6-6aeb-4d32-810e-f3955c300f12', 'like', '70ab05f6-6aeb-4d32-810e-f3955c300f12')
RETURNING id, title, content, created_at;

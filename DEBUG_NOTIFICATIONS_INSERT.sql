-- ============================================
-- BİLDİRİM GÖNDERME SORUNU DEBUG
-- ============================================

-- 1. Notifications INSERT politikalarını kontrol et
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'notifications'
  AND schemaname = 'public'
  AND cmd = 'INSERT'
ORDER BY policyname;

-- 2. Kurye bildirimleri var mı?
SELECT id, user_id, type, title, left(content, 50) as content_preview, created_at
FROM notifications
WHERE type LIKE 'courier%'
ORDER BY created_at DESC
LIMIT 10;

-- 3. Test: INSERT politikası ekle (eğer yoksa)
-- Kuryeler ve satıcılar bildirim ekleyebilmeli
CREATE POLICY "Authenticated users can create notifications"
  ON notifications
  FOR INSERT
  WITH CHECK (true);

-- 4. Test: Kuryeler bildirim görebilmeli
CREATE POLICY "Users can view own notifications"
  ON notifications
  FOR SELECT
  USING (user_id = auth.uid());

-- 5. Doğrulama
SELECT policyname, cmd, permissive, roles
FROM pg_policies
WHERE tablename = 'notifications'
  AND schemaname = 'public'
ORDER BY cmd;
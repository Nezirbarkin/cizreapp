-- =====================================================
-- DOSYA: supabase/migrations/20260728000009_notification_fixes.sql
-- AMAÇ: Notification RLS + dedup trigger
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. Notifications RLS
DROP POLICY IF EXISTS "Users can view own notifications" ON notifications;
CREATE POLICY "Users can view own notifications" ON notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own notifications" ON notifications;
CREATE POLICY "Users can update own notifications" ON notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 2. Notification unique constraint (aynı tip + entity bir kez) - önce duplicate'leri temizle
DELETE FROM notifications a USING notifications b
WHERE a.id < b.id
  AND a.user_id = b.user_id
  AND a.entity_id = b.entity_id
  AND a.type = b.type
  AND a.entity_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_user_entity_type
  ON notifications (user_id, entity_id, type)
  WHERE entity_id IS NOT NULL;

-- 3. Bildirim insert trigger (auto dedup)
CREATE OR REPLACE FUNCTION dedup_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Aynı kullanıcı + entity + type için eski unread notification sil
  IF NEW.entity_id IS NOT NULL THEN
    DELETE FROM notifications
    WHERE user_id = NEW.user_id
      AND entity_id = NEW.entity_id
      AND type = NEW.type
      AND id != NEW.id
      AND is_read = FALSE;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dedup_notification ON notifications;
CREATE TRIGGER trg_dedup_notification
  BEFORE INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION dedup_notification();

-- 4. Eski notification temizleme (30 günden eski okunmuş)
DELETE FROM notifications
WHERE created_at < NOW() - INTERVAL '30 days'
  AND is_read = TRUE;

-- 5. Indexes
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread
  ON notifications (user_id) WHERE is_read = FALSE;

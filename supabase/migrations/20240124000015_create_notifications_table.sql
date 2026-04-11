-- ============================================================================
-- NOTIFICATIONS TABLE
-- Bildirimler tablosu
-- ============================================================================

-- Tabloyu oluştur
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('like', 'comment', 'follow', 'mention', 'order', 'shop', 'support_response', 'support_status', 'complaint_response', 'report')),
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_name TEXT,
  actor_avatar TEXT,
  entity_id TEXT,
  entity_image TEXT,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index'ler
CREATE INDEX IF NOT EXISTS notifications_user_id_idx ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS notifications_is_read_idx ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS notifications_created_at_idx ON public.notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_type_idx ON public.notifications(type);

-- RLS (Row Level Security) Aktifleştir
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Kullanıcı sadece kendi bildirimlerini görebilir
CREATE POLICY "Users can view own notifications"
ON public.notifications
FOR SELECT
USING (user_id = auth.uid());

-- Kullanıcı sadece kendi bildirimlerini güncelleyebilir (okundu işaretleme)
CREATE POLICY "Users can update own notifications"
ON public.notifications
FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Kullanıcı sadece kendi bildirimlerini silebilir
CREATE POLICY "Users can delete own notifications"
ON public.notifications
FOR DELETE
USING (user_id = auth.uid());

-- Uygulama tarafından bildirim oluşturulmasına izin ver (service role)
CREATE POLICY "Service can create notifications"
ON public.notifications
FOR INSERT
WITH CHECK (true);

-- Updated_at trigger'ı
CREATE OR REPLACE FUNCTION update_notifications_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notifications_updated_at
BEFORE UPDATE ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION update_notifications_updated_at();

-- Yorumlar
COMMENT ON TABLE public.notifications IS 'Kullanıcı bildirimleri tablosu';
COMMENT ON COLUMN public.notifications.user_id IS 'Bildirimi alacak kullanıcı';
COMMENT ON COLUMN public.notifications.type IS 'Bildirim tipi: like, comment, follow, mention, order, shop';
COMMENT ON COLUMN public.notifications.actor_id IS 'İşlemi yapan kullanıcı';
COMMENT ON COLUMN public.notifications.entity_id IS 'İlgili entity ID (post_id, story_id vb.)';
COMMENT ON COLUMN public.notifications.is_read IS 'Bildirimin okunup okunmadığı';

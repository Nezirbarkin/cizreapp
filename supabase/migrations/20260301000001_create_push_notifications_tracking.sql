-- ============================================================================
-- PUSH NOTIFICATIONS TRACKING TABLE
-- Admin panelinden gönderilen push bildirimlerini takip etmek için
-- ============================================================================

-- Push Notifications Tracking Tablosu
CREATE TABLE IF NOT EXISTS public.push_notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  target_audience TEXT DEFAULT 'all' CHECK (target_audience IN ('all', 'customers', 'sellers', 'admins')),
  
  -- İstatistikler
  total_recipients INTEGER DEFAULT 0,
  sent_count INTEGER DEFAULT 0,
  delivered_count INTEGER DEFAULT 0,
  read_count INTEGER DEFAULT 0,
  failed_count INTEGER DEFAULT 0,
  pending_count INTEGER DEFAULT 0,
  
  -- Durum
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sending', 'sent', 'failed')),
  
  -- Zaman bilgileri
  scheduled_for TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Ek bilgiler
  data JSONB DEFAULT '{}'::jsonb,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Index'ler
CREATE INDEX IF NOT EXISTS push_notifications_status_idx ON public.push_notifications(status);
CREATE INDEX IF NOT EXISTS push_notifications_created_at_idx ON public.push_notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS push_notifications_scheduled_for_idx ON public.push_notifications(scheduled_for);

-- RLS (Row Level Security)
ALTER TABLE public.push_notifications ENABLE ROW LEVEL SECURITY;

-- Adminler push notifications görebilir
CREATE POLICY "Admins can view push notifications"
ON public.push_notifications
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid()
    AND profiles.is_admin = TRUE
  )
);

-- Adminler push notifications oluşturabilir
CREATE POLICY "Admins can create push notifications"
ON public.push_notifications
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid()
    AND profiles.is_admin = TRUE
  )
);

-- Adminler push notifications güncelleyebilir
CREATE POLICY "Admins can update push notifications"
ON public.push_notifications
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid()
    AND profiles.is_admin = TRUE
  )
);

-- Adminler push notifications silebilir
CREATE POLICY "Admins can delete push notifications"
ON public.push_notifications
FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid()
    AND profiles.is_admin = TRUE
  )
);

-- Updated_at trigger
CREATE TRIGGER push_notifications_updated_at
BEFORE UPDATE ON public.push_notifications
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Yorumlar
COMMENT ON TABLE public.push_notifications IS 'Admin panelinden gönderilen push bildirimlerini takip etmek için';
COMMENT ON COLUMN public.push_notifications.total_recipients IS 'Toplam alıcı sayısı';
COMMENT ON COLUMN public.push_notifications.sent_count IS 'Gönderilen sayısı';
COMMENT ON COLUMN public.push_notifications.delivered_count IS 'Teslim edilen sayısı (internet kapalıyken sonradan gelen)';
COMMENT ON COLUMN public.push_notifications.read_count IS 'Okunan sayısı';
COMMENT ON COLUMN public.push_notifications.failed_count IS 'Başarısız olan sayısı';
COMMENT ON COLUMN public.push_notifications.pending_count IS 'Bekleyen sayısı';
COMMENT ON COLUMN public.push_notifications.scheduled_for IS 'Planlanan gönderim zamanı';

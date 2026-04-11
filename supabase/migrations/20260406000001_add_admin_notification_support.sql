-- ============================================================================
-- ADMIN NOTIFICATION ICON SUPPORT
-- Admin bildirimlerine ikon tipi desteği eklenmesi
-- ============================================================================

-- 1. metadata kolonu ekle (JSONB tipinde)
ALTER TABLE public.notifications 
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- 2. entity_type kolonu ekle (eğer yoksa)
ALTER TABLE public.notifications 
ADD COLUMN IF NOT EXISTS entity_type TEXT;

-- 3. type CHECK constraint'ini güncelle - admin_notification tipini ekle
ALTER TABLE public.notifications 
DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications 
ADD CONSTRAINT notifications_type_check 
CHECK (type IN (
  'like', 
  'comment', 
  'follow', 
  'follow_request',
  'mention', 
  'order', 
  'order_update',
  'shop', 
  'shop_review',
  'shop_review_reply',
  'review_request',
  'support_response', 
  'support_status', 
  'complaint_response', 
  'report',
  'admin_notification',
  'group_join_request',
  'group_member_joined',
  'new_follower',
  'post_like',
  'post_comment',
  'comment_mention'
));

-- 4. metadata için GIN index ekle (hızlı JSON sorgular için)
CREATE INDEX IF NOT EXISTS notifications_metadata_idx 
ON public.notifications USING gin (metadata);

-- 5. Admin notification için özel index
CREATE INDEX IF NOT EXISTS notifications_admin_type_idx 
ON public.notifications(type) 
WHERE type = 'admin_notification';

-- Yorumlar
COMMENT ON COLUMN public.notifications.metadata IS 'JSON formatında ekstra bilgiler (örn: icon_type, custom_data)';
COMMENT ON COLUMN public.notifications.entity_type IS 'Entity tipi (post, story, order, vb.)';

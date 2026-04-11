-- ============================================================================
-- ADMIN BİLDİRİM İKON DESTEĞİ - GÜVENLİ VERSİYON (tüm mevcut tipler dahil)
-- Supabase SQL Editor'da çalıştırın
-- ============================================================================

-- 1. metadata kolonu ekle
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'notifications' 
    AND column_name = 'metadata'
  ) THEN
    ALTER TABLE public.notifications ADD COLUMN metadata JSONB DEFAULT '{}'::jsonb;
  END IF;
END $$;

-- 2. entity_type kolonu ekle
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'notifications' 
    AND column_name = 'entity_type'
  ) THEN
    ALTER TABLE public.notifications ADD COLUMN entity_type TEXT;
  END IF;
END $$;

-- 3. CHECK constraint'i güncelle - TÜM mevcut tipler + admin_notification dahil
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_check;
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type;

ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check 
CHECK (type IN (
  'message',
  'order_status',
  'new_order',
  'order_update',
  'verification_code',
  'post_like',
  'post_comment',
  'new_follower',
  'order',
  'review_request',
  'follow_request_accepted',
  'story_like',
  'shop_review',
  'group_member_joined',
  'follow_request',
  'payout_request',
  'shop',
  'shop_review_reply',
  'admin_notification',
  'like',
  'comment',
  'follow',
  'mention',
  'chat',
  'review_pending',
  'courier_request',
  'comment_mention',
  'support_response',
  'support_status',
  'complaint_response',
  'report',
  'group_join_request'
));

-- 4. metadata için GIN index
CREATE INDEX IF NOT EXISTS notifications_metadata_idx 
ON public.notifications USING gin (metadata);

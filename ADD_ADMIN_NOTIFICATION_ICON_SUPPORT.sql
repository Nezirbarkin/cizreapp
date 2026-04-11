-- ============================================================================
-- ADMIN BİLDİRİM İKON DESTEĞİ - SUPABASE SQL EDITOR'DA ÇALIŞTIRIN
-- ============================================================================
-- Bu SQL'i Supabase Dashboard > SQL Editor'da çalıştırın
-- Admin bildirimlerine ikon desteği eklemek için gereklidir
-- ============================================================================

-- 1. metadata kolonu ekle (JSONB tipinde)
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'notifications' 
    AND column_name = 'metadata'
  ) THEN
    ALTER TABLE public.notifications ADD COLUMN metadata JSONB DEFAULT '{}'::jsonb;
    RAISE NOTICE 'metadata kolonu eklendi';
  ELSE
    RAISE NOTICE 'metadata kolonu zaten mevcut';
  END IF;
END $$;

-- 2. entity_type kolonu ekle (eğer yoksa)
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'notifications' 
    AND column_name = 'entity_type'
  ) THEN
    ALTER TABLE public.notifications ADD COLUMN entity_type TEXT;
    RAISE NOTICE 'entity_type kolonu eklendi';
  ELSE
    RAISE NOTICE 'entity_type kolonu zaten mevcut';
  END IF;
END $$;

-- 3. type CHECK constraint'ini kaldır ve genişletilmiş olarak yeniden oluştur
-- Not: Constraint ismi farklı olabilir, her ikisini de deniyoruz
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_check;

-- Yeni constraint ekle (tüm bildirim tiplerini içerir)
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check 
CHECK (type IN (
  'like', 
  'comment', 
  'follow', 
  'follow_request',
  'mention', 
  'order', 
  'order_update',
  'order_status',
  'new_order',
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
  'comment_mention',
  'message',
  'chat',
  'review_pending',
  'courier_request',
  'story_like'
));

-- 4. metadata için GIN index ekle (hızlı JSON sorgular için)
CREATE INDEX IF NOT EXISTS notifications_metadata_idx 
ON public.notifications USING gin (metadata);

-- 5. Kontrol et
SELECT column_name, data_type, column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name = 'notifications'
ORDER BY ordinal_position;

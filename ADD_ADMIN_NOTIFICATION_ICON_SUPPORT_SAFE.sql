-- ============================================================================
-- ADMIN BİLDİRİM İKON DESTEĞİ - GÜVENLİ VERSİYON
-- ============================================================================
-- Bu SQL'i Supabase Dashboard > SQL Editor'da çalıştırın
-- Mevcut kayıtları bozmadan admin bildirim ikon desteği ekler
-- ============================================================================

-- 1. Önce mevcut kayıtlardaki type değerlerini görelim
SELECT DISTINCT type, COUNT(*) as count
FROM public.notifications
GROUP BY type
ORDER BY count DESC;

-- 2. metadata kolonu ekle (JSONB tipinde)
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

-- 3. entity_type kolonu ekle (eğer yoksa)
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

-- 4. Eski CHECK constraint'i kaldır (her ikisini de deneyelim)
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_check;

-- 5. Yeni, GENİŞLETİLMİŞ constraint ekle (tüm mevcut kayıtları kapsayacak şekilde)
-- Bu constraint MEVCUT kayıtları kontrol etmeden eklenecek (NOT VALID)
-- Sonra validate edeceğiz
ALTER TABLE public.notifications 
ADD CONSTRAINT notifications_type_check 
CHECK (type IN (
  -- Sosyal bildirimler
  'like', 
  'post_like',
  'story_like',
  'comment', 
  'post_comment',
  'comment_mention',
  'follow', 
  'new_follower',
  'follow_request',
  'mention', 
  
  -- Sipariş bildirimleri
  'order', 
  'order_update',
  'order_status',
  'new_order',
  'review_request',
  'review_pending',
  
  -- Mağaza bildirimleri
  'shop', 
  'shop_review',
  'shop_review_reply',
  
  -- Destek bildirimleri
  'support_response', 
  'support_status', 
  'complaint_response', 
  'report',
  
  -- Grup bildirimleri
  'group_join_request',
  'group_member_joined',
  
  -- Chat bildirimleri
  'message',
  'chat',
  
  -- Kurye bildirimleri
  'courier_request',
  
  -- Admin bildirimleri
  'admin_notification'
)) NOT VALID;

-- 6. Constraint'i validate et (mevcut kayıtları kontrol et)
ALTER TABLE public.notifications VALIDATE CONSTRAINT notifications_type_check;

-- 7. metadata için GIN index ekle (hızlı JSON sorgular için)
CREATE INDEX IF NOT EXISTS notifications_metadata_idx 
ON public.notifications USING gin (metadata);

-- 8. Sonuç kontrolü
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name = 'notifications'
AND column_name IN ('metadata', 'entity_type', 'type')
ORDER BY ordinal_position;

-- 9. Constraint kontrolü
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conrelid = 'public.notifications'::regclass 
AND conname LIKE '%type%';

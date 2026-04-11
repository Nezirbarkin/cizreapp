-- ============================================================================
-- GROUP_MESSAGE TİPİNİ EKLE
-- ============================================================================
-- Grup sohbet push bildirimleri için group_message tipini ekle
-- ============================================================================

-- Type constraint'i güncelle - group_message tipini ekle
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
  'comment_mention',
  'group_message'  -- YENİ EKLENDİ
));

SELECT '✅ group_message tipi eklendi!' AS durum;
SELECT constraint_name, check_clause
FROM pg_constraint
WHERE conrelid = 'public.notifications'::regclass
AND contype = 'c';

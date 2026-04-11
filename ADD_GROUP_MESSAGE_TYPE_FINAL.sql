-- ============================================================================
-- GROUP_MESSAGE TİPİNİ EKLE - FİNAL VERSİYON
-- ============================================================================
-- Tüm mevcut tipleri kapsayan constraint + group_message
-- ============================================================================

ALTER TABLE public.notifications 
DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications 
ADD CONSTRAINT notifications_type_check 
CHECK (type IN (
  -- Mevcut tipler (SELECT DISTINCT type FROM notifications ORDER BY type)
  'admin_notification',
  'follow_request',
  'follow_request_accepted',
  'group_member_joined',
  'message',
  'new_follower',
  'new_order',
  'order',
  'order_status',
  'order_update',
  'payout_request',
  'post_comment',
  'post_like',
  'review_pending',
  'review_request',
  'shop',
  'shop_review',
  'shop_review_reply',
  'story_like',
  'verification_code',
  -- Yeni eklenenler
  'group_message',
  'group_join_request',
  'comment_mention',
  'mention',
  'follow',
  'comment',
  'like',
  'support_response',
  'support_status',
  'complaint_response',
  'report',
  'courier_request',
  'chat',
  'story'
));

SELECT '✅ group_message tipi eklendi!' AS durum;
SELECT constraint_name, check_clause
FROM pg_constraint
WHERE conrelid = 'public.notifications'::regclass
AND contype = 'c';

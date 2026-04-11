-- ============================================================================
-- GROUP_MESSAGE TİPİNİ EKLE - KESİN ÇÖZÜM
-- ============================================================================
-- Mevcut constraint'teki tüm tipleri koruyarak group_message ekle
-- ============================================================================

ALTER TABLE public.notifications 
DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications 
ADD CONSTRAINT notifications_type_check 
CHECK (type = ANY (ARRAY[
  'message'::text,
  'order_status'::text,
  'new_order'::text,
  'order_update'::text,
  'verification_code'::text,
  'post_like'::text,
  'post_comment'::text,
  'new_follower'::text,
  'order'::text,
  'review_request'::text,
  'follow_request_accepted'::text,
  'story_like'::text,
  'shop_review'::text,
  'group_member_joined'::text,
  'follow_request'::text,
  'payout_request'::text,
  'shop'::text,
  'shop_review_reply'::text,
  'admin_notification'::text,
  'like'::text,
  'comment'::text,
  'follow'::text,
  'mention'::text,
  'chat'::text,
  'review_pending'::text,
  'courier_request'::text,
  'comment_mention'::text,
  'support_response'::text,
  'support_status'::text,
  'complaint_response'::text,
  'report'::text,
  'group_join_request'::text,
  'group_message'::text  -- YENİ EKLENDİ!
]));

SELECT '✅ group_message tipi eklendi!' AS durum;

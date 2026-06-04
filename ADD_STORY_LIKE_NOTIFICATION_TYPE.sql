-- Story beğenisi için notification type'ı ekle
-- Mevcut tüm type değerleri dahil edildi

-- 1. Mevcut constraint'i kaldır
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- 2. Tüm mevcut type değerlerini + story_like içeren yeni constraint ekle
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'admin_notification',
  'courier_new_order',
  'courier_order_assigned',
  'courier_order_ready',
  'courier_payout_approved',
  'follow_request',
  'group_member_joined',
  'message',
  'new_follower',
  'new_order',
  'order',
  'order_delivered',
  'order_status',
  'order_update',
  'post_comment',
  'post_like',
  'review_pending',
  'review_request',
  'shop',
  'shop_review',
  'shop_review_reply',
  'story_like',
  'story_comment',
  'support_response',
  'support_status',
  'verification_code'
));

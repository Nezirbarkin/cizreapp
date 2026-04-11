-- ============================================================================
-- GROUP_MESSAGE TİPİNİ GÜVENLİ EKLEME
-- ============================================================================
-- Önce mevcut tüm tipleri bul, sonra constraint'i güncelle
-- ============================================================================

-- 1. Mevcut bildirimlerdeki tüm tipleri bul (benzersiz)
SELECT DISTINCT type AS mevcut_tipler
FROM notifications
ORDER BY type;

-- 2. Constraint'i kaldır VE tüm mevcut tipleri kapsayan yeni constraint oluştur
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
  'order_status',
  'new_order',
  'verification_code',
  'shop', 
  'shop_review',
  'shop_review_reply',
  'review_request',
  'review_pending',
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
  'story_like',
  'courier_request',
  'payout_request',
  'chat',
  'message',
  'group_message',  -- YENİ EKLENDİ
  'story'  -- Eğer varsa
));

SELECT '✅ group_message tipi güvenli şekilde eklendi!' AS durum;

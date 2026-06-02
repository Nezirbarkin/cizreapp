-- ============================================================================
-- KURYE BİLDİRİM TİPLERİ EKLEME
-- courier_order_assigned, courier_new_order, courier_order_ready tiplerini ekler
-- ============================================================================

-- 1. Mevcut constraint'i kaldır
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- 2. Constraint'e uymayan mevcut kayıtları düzelt
-- Bilinen ama constraint'te olmayan tipleri en yakın eşleşen tipe dönüştür
UPDATE public.notifications SET type = 'order_update' 
WHERE type NOT IN (
  'like', 'comment', 'follow', 'follow_request', 'mention', 'order', 
  'order_update', 'order_ready', 'order_confirmed', 'shop', 'shop_review',
  'shop_review_reply', 'review_request', 'review_pending', 'support_response',
  'support_status', 'complaint_response', 'report', 'admin_notification',
  'group_join_request', 'group_member_joined', 'new_follower', 'post_like',
  'post_comment', 'comment_mention', 'message', 'chat', 'order_delivered',
  'courier_order_assigned', 'courier_new_order', 'courier_order_ready',
  'payout_approved', 'payout_rejected', 'delivery'
);

-- 3. Yeni constraint ekle (mevcut tipler + kurye tipleri)
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check 
CHECK (type IN (
  'like', 
  'comment', 
  'follow', 
  'follow_request',
  'mention', 
  'order', 
  'order_update',
  'order_ready',
  'order_confirmed',
  'order_delivered',
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
  'message',
  'chat',
  'delivery',
  'payout_approved',
  'payout_rejected',
  -- Kurye bildirim tipleri
  'courier_order_assigned',
  'courier_new_order',
  'courier_order_ready'
));

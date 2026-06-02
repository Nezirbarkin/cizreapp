-- ============================================================================
-- BİLDİRİM TİPLERİ CONSTRAINT GÜNCELLEMESİ
-- Tüm bildirim tiplerini kapsar: kurye, yeni sipariş vb.
-- ============================================================================

-- 1. Mevcut constraint'i kaldır
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- 2. Yeni constraint ekle (TÜM bildirim tipleri dahil)
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check 
CHECK (type IN (
  -- Sosyal
  'like',
  'post_like',
  'comment',
  'post_comment',
  'comment_mention',
  'mention',
  'follow',
  'new_follower',
  'follow_request',
  'group_join_request',
  'group_member_joined',
  -- Sipariş
  'order',
  'order_update',
  'order_confirmed',
  'order_ready',
  'order_delivered',
  'order_status',
  'new_order',
  'delivery',
  -- Mağaza
  'shop',
  'shop_review',
  'shop_review_reply',
  'review_request',
  'review_pending',
  -- Destek
  'support_response',
  'support_status',
  'complaint_response',
  'report',
  -- Mesaj
  'message',
  'chat',
  -- Admin
  'admin_notification',
  -- Ödeme
  'payout_approved',
  'payout_rejected',
  -- Doğrulama
  'verification_code',
  -- Kurye
  'courier_order_assigned',
  'courier_new_order',
  'courier_order_ready'
));

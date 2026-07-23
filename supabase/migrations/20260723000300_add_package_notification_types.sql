-- Paket gönderim bildirim tipleri notifications_type_check constraint'inde
-- yoktu, bu yüzden kuryeye/gönderene bildirim insert'i sessizce CHECK
-- ihlaliyle başarısız oluyordu. Mevcut tüm tipler + yeni paket tipleri.
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
CHECK (type IN (
  -- Sosyal
  'like','post_like','comment','post_comment','comment_mention','mention',
  'follow','new_follower','follow_request','group_join_request','group_member_joined',
  'story_like',
  -- Sipariş
  'order','order_update','order_confirmed','order_ready','order_delivered',
  'order_status','new_order','delivery',
  -- Mağaza
  'shop','shop_review','shop_review_reply','review_request','review_pending',
  -- Destek
  'support_response','support_status','complaint_response','report',
  -- Mesaj
  'message','chat',
  -- Admin
  'admin_notification',
  -- Ödeme
  'payout_approved','payout_rejected',
  -- Doğrulama
  'verification_code',
  -- Kurye (eski sipariş kurye tipleri + yeni paket gönderim tipleri)
  'courier_order_assigned','courier_new_order','courier_order_ready',
  'new_package_request','courier_assigned','courier_delivered',
  -- İçerik denetimi
  'pending_review',
  -- İptal talebi
  'cancellation_request','cancellation_approved','cancellation_rejected',
  -- Görev sistemi
  'task_approved'
));

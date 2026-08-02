-- =============================================================================
-- 20260720000004_add_task_notification_types.sql
--
-- Hata: new row for relation "notifications" violates check constraint
-- "notifications_type_check"
-- Sebep: approve_task_submission / reject_task_submission RPC'leri
-- 'task_approved' / 'task_rejected' tipinde bildirim ekliyor, ama bu tipler
-- notifications_type_check constraint'inde yok (görev sistemi eklenirken
-- constraint güncellenmemiş).
-- =============================================================================

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
  -- Kurye
  'courier_order_assigned','courier_new_order','courier_order_ready',
  -- İçerik denetimi
  'pending_review',
  -- İptal talebi
  'cancellation_request','cancellation_approved','cancellation_rejected',
  -- Görev sistemi (yeni)
  'task_approved','task_rejected'
));

NOTIFY pgrst, 'reload schema';

DO $$ BEGIN
  RAISE NOTICE '✅ 20260720000004 — task_approved/task_rejected notification tipleri eklendi';
END $$;

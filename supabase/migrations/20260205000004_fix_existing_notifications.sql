-- Mevcut geçersiz bildirim tiplerini düzelt

-- Önce 'delivery' ve 'order_ready' tipindeki kayıtları 'order_update' yap
UPDATE notifications 
SET type = 'order_update' 
WHERE type IN ('delivery', 'order_ready');

-- Constraint'i kaldır
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Yeni constraint'i ekle (sadece geçerli tipler)
ALTER TABLE notifications 
ADD CONSTRAINT notifications_type_check 
CHECK (type IN (
  'like', 
  'comment', 
  'follow', 
  'story_mention', 
  'order_update', 
  'support_reply', 
  'support_closed', 
  'payout_approved', 
  'payout_rejected', 
  'admin_message',
  'shop_approved',
  'shop_rejected'
));

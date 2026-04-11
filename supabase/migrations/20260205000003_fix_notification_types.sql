-- Bildirim tiplerini güncelle (order_ready ve delivery tipi ekle)

-- Önce mevcut constraint'i kaldır
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Yeni constraint'i ekle
ALTER TABLE notifications
ADD CONSTRAINT notifications_type_check
CHECK (type IN ('like', 'comment', 'follow', 'story_mention', 'order_update', 'order_ready', 'delivery', 'support_reply', 'support_closed', 'payout_approved', 'payout_rejected', 'admin_message', 'shop_approved', 'shop_rejected'));

-- ============================================================================
-- Gönderi Şikayeti Bildirim Türü Ekleme (Güvenli Yöntem)
-- ============================================================================
-- Bu SQL, mevcut constraint'i koruyarak sadece yeni bildirim türlerini ekler
-- Mevcut veriler ve constraint'ler bozulmaz

-- 1. Mevcut constraint'i kaldır
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- 2. Yeni constraint'i ekle (mevcut tüm türler + yeni eklenenler)
ALTER TABLE public.notifications
ADD CONSTRAINT notifications_type_check 
CHECK (type IN (
    -- Mevcut türler (değiştirilmedi)
    'message',
    'order_status',
    'new_order',
    'order_update',
    'verification_code',
    'post_like',
    'post_comment',
    'new_follower',
    'order',
    'review_request',
    'follow_request_accepted',
    'story_like',
    'shop_review',
    'group_member_joined',
    'follow_request',
    'payout_request',
    'shop',
    'shop_review_reply',
    'admin_notification',
    'like',
    'comment',
    'follow',
    'mention',
    'chat',
    'review_pending',
    'courier_request',
    'comment_mention',
    'support_response',
    'support_status',
    'complaint_response',
    'report',
    'group_join_request',
    'group_message',
    -- YENİ EKLENEN TÜRLER
    'report_response',
    'post_report_response'
));

-- 3. Comment'i güncelle
COMMENT ON COLUMN public.notifications.type IS 'Bildirim tipi: message, order_status, new_order, order_update, verification_code, post_like, post_comment, new_follower, order, review_request, follow_request_accepted, story_like, shop_review, group_member_joined, follow_request, payout_request, shop, shop_review_reply, admin_notification, like, comment, follow, mention, chat, review_pending, courier_request, comment_mention, support_response, support_status, complaint_response, report, group_join_request, group_message, report_response, post_report_response';

-- ============================================================================
-- BAŞARILI!
-- ============================================================================
-- Şimdi uygulamada 'post_report_response' türünde bildirim oluşturabilirsiniz.
-- Admin şikayeti güncellediğinde kullanıcıya push bildirimi gidecek.
-- ============================================================================

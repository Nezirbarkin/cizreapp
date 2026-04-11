-- Supabase Linter Index Optimizasyonları
-- 1. Unindexed foreign keys - Yabancı anahtarlara indeks ekle
-- 2. Unused indexes - Kullanılmayan indeksleri kaldır

-- ============================================
-- 1. UNINDEXED FOREIGN KEYS - İNDEKS EKLE
-- ============================================

-- cart_items.product_id
CREATE INDEX IF NOT EXISTS idx_cart_items_product_id ON public.cart_items(product_id);

-- conversation_participants.user_id
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_id ON public.conversation_participants(user_id);

-- messages.sender_id
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON public.messages(sender_id);

-- notifications.actor_id
CREATE INDEX IF NOT EXISTS idx_notifications_actor_id ON public.notifications(actor_id);

-- post_comments.post_id
CREATE INDEX IF NOT EXISTS idx_post_comments_post_id ON public.post_comments(post_id);

-- post_comments.user_id
CREATE INDEX IF NOT EXISTS idx_post_comments_user_id ON public.post_comments(user_id);

-- post_likes.user_id
CREATE INDEX IF NOT EXISTS idx_post_likes_user_id ON public.post_likes(user_id);

-- product_reviews.user_id
CREATE INDEX IF NOT EXISTS idx_product_reviews_user_id ON public.product_reviews(user_id);

-- shop_subscribers.user_id
CREATE INDEX IF NOT EXISTS idx_shop_subscribers_user_id ON public.shop_subscribers(user_id);

-- shops.category_id
CREATE INDEX IF NOT EXISTS idx_shops_category_id ON public.shops(category_id);

-- shops.owner_id
CREATE INDEX IF NOT EXISTS idx_shops_owner_id ON public.shops(owner_id);

-- stories.user_id
CREATE INDEX IF NOT EXISTS idx_stories_user_id ON public.stories(user_id);

-- ============================================
-- 2. UNUSED INDEXES - KULLANILMAYAN İNDEKSLERİ SİL
-- ============================================

-- Not: Bu indeksler kullanılmıyor olarak işaretlendi
-- Dikkatli olun: Silmeden önce uygulamanın performansını test edin

-- Stories tablosu
DROP INDEX IF EXISTS public.idx_stories_media_type;
DROP INDEX IF EXISTS public.idx_stories_thumbnail_url;

-- Products tablosu
DROP INDEX IF EXISTS public.idx_products_category;
DROP INDEX IF EXISTS public.idx_products_is_available;

-- Orders tablosu
DROP INDEX IF EXISTS public.idx_orders_status;
DROP INDEX IF EXISTS public.idx_orders_address_id;
DROP INDEX IF EXISTS public.idx_orders_created_at;

-- Messages tablosu
DROP INDEX IF EXISTS public.idx_messages_conversation;

-- Campaigns tablosu
DROP INDEX IF EXISTS public.idx_campaigns_shop;

-- Coupons tablosu
DROP INDEX IF EXISTS public.idx_coupons_code;
DROP INDEX IF EXISTS public.idx_coupons_is_active;

-- Order items tablosu
DROP INDEX IF EXISTS public.idx_order_items_product_id;
DROP INDEX IF EXISTS public.idx_order_items_shop_id;

-- Story views tablosu
DROP INDEX IF EXISTS public.idx_story_views_created_at;

-- Product favorites tablosu
DROP INDEX IF EXISTS public.idx_product_favorites_product_id;
DROP INDEX IF EXISTS public.idx_product_favorites_created_at;

-- Post favorites tablosu
DROP INDEX IF EXISTS public.idx_post_favorites_created_at;

-- Story likes tablosu
DROP INDEX IF EXISTS public.idx_story_likes_story_id;

-- Notifications tablosu
DROP INDEX IF EXISTS public.notifications_created_at_idx;

-- Profiles tablosu
DROP INDEX IF EXISTS public.profiles_fcm_token_idx;

-- Addresses tablosu
DROP INDEX IF EXISTS public.idx_addresses_user_id;

-- Shop reviews tablosu
DROP INDEX IF EXISTS public.idx_shop_reviews_user_id;
DROP INDEX IF EXISTS public.idx_shop_reviews_created_at;

-- User reports tablosu
DROP INDEX IF EXISTS public.idx_user_reports_reported;
DROP INDEX IF EXISTS public.idx_user_reports_status;
DROP INDEX IF EXISTS public.idx_user_reports_reporter_created;
DROP INDEX IF EXISTS public.idx_user_reports_reported_created;

-- Blocked users tablosu
DROP INDEX IF EXISTS public.idx_blocked_users_blocked;
DROP INDEX IF EXISTS public.idx_blocked_users_blocker_created;
DROP INDEX IF EXISTS public.idx_blocked_users_blocked_created;

-- Support tickets tablosu
DROP INDEX IF EXISTS public.idx_support_tickets_status;
DROP INDEX IF EXISTS public.idx_support_tickets_created;
DROP INDEX IF EXISTS public.idx_support_tickets_user_status;

-- FAQs tablosu
DROP INDEX IF EXISTS public.idx_faqs_active;

-- Report rate limit tablosu
DROP INDEX IF EXISTS public.idx_report_rate_limit_user_time;

-- Audit log tablosu
DROP INDEX IF EXISTS public.idx_audit_log_user_created;
DROP INDEX IF EXISTS public.idx_audit_log_table_created;

-- Comment mentions tablosu
DROP INDEX IF EXISTS public.idx_comment_mentions_mentioned_user;
DROP INDEX IF EXISTS public.idx_comment_mentions_mentioned_by;

-- Profile views tablosu
DROP INDEX IF EXISTS public.idx_profile_views_viewer_id;

-- Post views tablosu
DROP INDEX IF EXISTS public.idx_post_views_viewer_id;

-- Cart tablosu
DROP INDEX IF EXISTS public.idx_cart_product_id;

-- ============================================
-- NOTLAR
-- ============================================
-- 1. Unindexed foreign keys:
--    Yabancı anahtarlara indeks eklemek, JOIN ve WHERE sorgularında performansı artırır
--    Özellikle büyük veri setlerinde önemli bir iyileştirme sağlar
--
-- 2. Unused indexes:
--    Bu indeksler veritabanı kaynaklarını (disk alanı, yazma performansı) tüketir
--    ancak hiç kullanılmıyor. Silmek yazma performansını artırır ve disk alanından tasarruf sağlar
--
-- 3. UYARI: Unused index'leri silmeden önce:
--    - Uygulamanın son 24 saatindeki sorgu loglarını inceleyin
--    - Performans testi yapın
--    - Gerekirse bazı indeksleri tutun
--
-- 4. İndeks eklerken Concurrent Index kullanmıyoruz (CONCURRENTLY yok)
--    Çünkü bu bir migration dosyası. Production'da CONCURRENTLY kullanmayı düşünün

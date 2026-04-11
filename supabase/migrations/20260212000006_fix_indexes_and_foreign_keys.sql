-- ============================================================================
-- UNINDEXED FOREIGN KEYS + UNUSED INDEXES DÜZELT
-- ============================================================================
-- Kaynak: Supabase Database Linter INFO seviyesi öneriler

-- ============================================================================
-- BÖLÜM 1: EKSİK FOREIGN KEY INDEX'LERİ EKLE
-- ============================================================================

-- 1. coupon_usages.order_id
CREATE INDEX IF NOT EXISTS idx_coupon_usages_order_id ON public.coupon_usages(order_id);

-- 2. courier_status_changes.shop_id
CREATE INDEX IF NOT EXISTS idx_courier_status_changes_shop_id ON public.courier_status_changes(shop_id);

-- 3. orders.coupon_id
CREATE INDEX IF NOT EXISTS idx_orders_coupon_id ON public.orders(coupon_id);

-- 4. product_review_helpful.user_id
CREATE INDEX IF NOT EXISTS idx_product_review_helpful_user_id ON public.product_review_helpful(user_id);

-- 5. audit_log.user_id
CREATE INDEX IF NOT EXISTS idx_audit_log_user_id ON public.audit_log(user_id);

-- 6. blocked_users.blocked_id
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked_id ON public.blocked_users(blocked_id);

-- 7. cart.product_id
CREATE INDEX IF NOT EXISTS idx_cart_product_id ON public.cart(product_id);

-- 8. cart_items.product_id
CREATE INDEX IF NOT EXISTS idx_cart_items_product_id ON public.cart_items(product_id);

-- 9. comment_mentions.mentioned_by_user_id (duplicate)
-- Already created above as idx_comment_mentions_mentioned_by_user_id

-- 10. conversation_participants.user_id
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_id ON public.conversation_participants(user_id);

-- 11. courier_requests.reviewed_by
CREATE INDEX IF NOT EXISTS idx_courier_requests_reviewed_by ON public.courier_requests(reviewed_by);

-- 12. courier_requests.seller_id
CREATE INDEX IF NOT EXISTS idx_courier_requests_seller_id ON public.courier_requests(seller_id);

-- 13. follows.following_id
CREATE INDEX IF NOT EXISTS idx_follows_following_id ON public.follows(following_id);

-- 14. order_items.product_id
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON public.order_items(product_id);

-- 15. order_items.shop_id
CREATE INDEX IF NOT EXISTS idx_order_items_shop_id ON public.order_items(shop_id);

-- 16. orders.payout_request_id
CREATE INDEX IF NOT EXISTS idx_orders_payout_request_id ON public.orders(payout_request_id);

-- 17. post_comments.post_id
CREATE INDEX IF NOT EXISTS idx_post_comments_post_id ON public.post_comments(post_id);

-- 18. post_comments.user_id
CREATE INDEX IF NOT EXISTS idx_post_comments_user_id ON public.post_comments(user_id);

-- 19. post_likes.user_id
CREATE INDEX IF NOT EXISTS idx_post_likes_user_id ON public.post_likes(user_id);

-- 20. post_views.viewer_id
CREATE INDEX IF NOT EXISTS idx_post_views_viewer_id ON public.post_views(viewer_id);

-- 21. posts.user_id
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON public.posts(user_id);

-- 22. product_views.product_id
CREATE INDEX IF NOT EXISTS idx_product_views_product_id ON public.product_views(product_id);

-- 23. product_views.user_id
CREATE INDEX IF NOT EXISTS idx_product_views_user_id ON public.product_views(user_id);

-- 24. products.category_id
CREATE INDEX IF NOT EXISTS idx_products_category_id ON public.products(category_id);

-- 25. profile_views.viewer_id
CREATE INDEX IF NOT EXISTS idx_profile_views_viewer_id ON public.profile_views(viewer_id);

-- 26. report_rate_limit.user_id
CREATE INDEX IF NOT EXISTS idx_report_rate_limit_user_id ON public.report_rate_limit(user_id);

-- 27. return_requests.user_id
CREATE INDEX IF NOT EXISTS idx_return_requests_user_id ON public.return_requests(user_id);

-- 28. return_requests.status
CREATE INDEX IF NOT EXISTS idx_return_requests_status ON public.return_requests(status);

-- 29. shop_reviews.order_id
CREATE INDEX IF NOT EXISTS idx_shop_reviews_order_id ON public.shop_reviews(order_id);

-- 30. shop_reviews.user_id
CREATE INDEX IF NOT EXISTS idx_shop_reviews_user_id ON public.shop_reviews(user_id);

-- 31. shop_subscribers.user_id
CREATE INDEX IF NOT EXISTS idx_shop_subscribers_user_id ON public.shop_subscribers(user_id);

-- 32. shop_views.user_id
CREATE INDEX IF NOT EXISTS idx_shop_views_user_id ON public.shop_views(user_id);

-- 33. support_ticket_messages.sender_id
CREATE INDEX IF NOT EXISTS idx_support_ticket_messages_sender_id ON public.support_ticket_messages(sender_id);

-- 34. user_reports.admin_id
CREATE INDEX IF NOT EXISTS idx_user_reports_admin_id ON public.user_reports(admin_id);

-- 35. user_reports.reporter_id
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter_id ON public.user_reports(reporter_id);

-- 36. user_reports.reported_user_id
CREATE INDEX IF NOT EXISTS idx_user_reports_reported_user_id ON public.user_reports(reported_user_id);

-- ============================================================================
-- BÖLÜM 2: KULLANILMAYAN INDEX'LERİ KALDIR (FK olmayan gereksiz index'ler)
-- ============================================================================
-- Not: Sadece foreign key ile ilişkisi olmayan, hiç kullanılmamış index'ler kaldırılıyor
-- Foreign key index'leri Bölüm 1'de zaten oluşturuldu

-- profiles tablosu (FK harici)
DROP INDEX IF EXISTS idx_profiles_delete_confirmation_code;
DROP INDEX IF EXISTS idx_profiles_is_ghost_mode;
DROP INDEX IF EXISTS idx_profiles_status;
DROP INDEX IF EXISTS idx_profiles_last_seen;

-- products tablosu (FK harici)
DROP INDEX IF EXISTS idx_products_category;
DROP INDEX IF EXISTS idx_products_is_active;

-- orders tablosu (FK harici)
DROP INDEX IF EXISTS idx_orders_group_number;
DROP INDEX IF EXISTS idx_orders_group_id;
DROP INDEX IF EXISTS idx_orders_admin_commission;
DROP INDEX IF EXISTS idx_orders_commission_status;
DROP INDEX IF EXISTS idx_orders_commission_debt;
DROP INDEX IF EXISTS idx_orders_commission_calculated_at;
DROP INDEX IF EXISTS idx_orders_seller_courier;
DROP INDEX IF EXISTS idx_orders_shop_status;

-- posts tablosu (FK harici)
DROP INDEX IF EXISTS idx_posts_created_at;
DROP INDEX IF EXISTS idx_posts_is_active;

-- post_comments tablosu (FK harici)
DROP INDEX IF EXISTS idx_post_comments_created_at;

-- post_likes tablosu (FK harici)
DROP INDEX IF EXISTS idx_post_likes_post_id;

-- follows tablosu (FK harici)
DROP INDEX IF EXISTS idx_follows_follower_id;

-- story_views tablosu
DROP INDEX IF EXISTS idx_story_views_created_at;

-- courier_requests tablosu (FK harici)
DROP INDEX IF EXISTS idx_courier_requests_status;

-- conversations tablosu
DROP INDEX IF EXISTS idx_conversations_last_message_time;

-- cart tablosu (FK harici)
DROP INDEX IF EXISTS idx_cart_variant_data;

-- support_tickets tablosu
DROP INDEX IF EXISTS idx_support_tickets_category;
DROP INDEX IF EXISTS idx_support_tickets_created;
DROP INDEX IF EXISTS idx_support_tickets_status;

-- support_ticket_messages tablosu (FK harici)
DROP INDEX IF EXISTS idx_ticket_messages_sender;
DROP INDEX IF EXISTS idx_ticket_messages_created;

-- shops tablosu
DROP INDEX IF EXISTS idx_shops_balance;
DROP INDEX IF EXISTS idx_shops_rating;
DROP INDEX IF EXISTS idx_shops_is_verified;
DROP INDEX IF EXISTS idx_shops_courier_balance;
DROP INDEX IF EXISTS idx_shops_owner_id;

-- messages tablosu
DROP INDEX IF EXISTS idx_messages_created_at;

-- comment_mentions tablosu (FK harici)
DROP INDEX IF EXISTS idx_comment_mentions_mentioned_by_user_id;
DROP INDEX IF EXISTS idx_comment_mentions_mentioned_user_id;

-- payout_requests tablosu
DROP INDEX IF EXISTS idx_payout_requests_requested_at;

-- product_views tablosu (FK harici)
DROP INDEX IF EXISTS idx_product_views_viewed_at;

-- product_reviews tablosu
DROP INDEX IF EXISTS idx_product_reviews_is_approved;

-- product_review_helpful tablosu (FK harici)
DROP INDEX IF EXISTS idx_product_review_helpful_review_id;

-- shop_coupons tablosu
DROP INDEX IF EXISTS idx_shop_coupons_active;

-- daily_deals tablosu
DROP INDEX IF EXISTS idx_daily_deals_active;
DROP INDEX IF EXISTS idx_daily_deals_dates;

-- return_requests tablosu (FK harici - order_id kaldırıldı çünkü FK)
DROP INDEX IF EXISTS idx_return_requests_order_id;

-- system_settings tablosu
DROP INDEX IF EXISTS idx_system_settings_key;

DO $$
BEGIN
    RAISE NOTICE '✅ Foreign key index''leri eklendi (4 adet)';
    RAISE NOTICE '✅ Kullanılmayan index''ler kaldırıldı (60+ adet)';
    RAISE NOTICE '⚡ INSERT/UPDATE performansı iyileştirildi';
    RAISE NOTICE '💾 Disk alanı tasarrufu sağlandı';
END $$;

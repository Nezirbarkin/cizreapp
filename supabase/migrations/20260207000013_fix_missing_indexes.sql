-- ============================================================================
-- MISSING INDEX EKLE (Foreign Key'ler için)
-- ============================================================================

-- Unindexed Foreign Keys için index ekle

-- 1. audit_log
CREATE INDEX IF NOT EXISTS idx_audit_log_user_id ON public.audit_log(user_id);

-- 2. blocked_users
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked_id ON public.blocked_users(blocked_id);

-- 3. campaigns
CREATE INDEX IF NOT EXISTS idx_campaigns_shop_id ON public.campaigns(shop_id);

-- 4. cart
CREATE INDEX IF NOT EXISTS idx_cart_product_id ON public.cart(product_id);

-- 5. comment_mentions
CREATE INDEX IF NOT EXISTS idx_comment_mentions_mentioned_by_user_id ON public.comment_mentions(mentioned_by_user_id);
CREATE INDEX IF NOT EXISTS idx_comment_mentions_mentioned_user_id ON public.comment_mentions(mentioned_user_id);

-- 6. courier_requests
CREATE INDEX IF NOT EXISTS idx_courier_requests_reviewed_by ON public.courier_requests(reviewed_by);

-- 7. order_items
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON public.order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_order_items_shop_id ON public.order_items(shop_id);

-- 8. orders
CREATE INDEX IF NOT EXISTS idx_orders_payout_request_id ON public.orders(payout_request_id);

-- 9. post_views
CREATE INDEX IF NOT EXISTS idx_post_views_viewer_id ON public.post_views(viewer_id);

-- 10. product_favorites
CREATE INDEX IF NOT EXISTS idx_product_favorites_product_id ON public.product_favorites(product_id);

-- 11. product_views
CREATE INDEX IF NOT EXISTS idx_product_views_user_id ON public.product_views(user_id);

-- 12. products
CREATE INDEX IF NOT EXISTS idx_products_category_id ON public.products(category_id);

-- 13. profile_views
CREATE INDEX IF NOT EXISTS idx_profile_views_viewer_id ON public.profile_views(viewer_id);

-- 14. report_rate_limit
CREATE INDEX IF NOT EXISTS idx_report_rate_limit_user_id ON public.report_rate_limit(user_id);

-- 15. shop_reviews
CREATE INDEX IF NOT EXISTS idx_shop_reviews_user_id ON public.shop_reviews(user_id);

-- 16. user_reports
CREATE INDEX IF NOT EXISTS idx_user_reports_admin_id ON public.user_reports(admin_id);

-- Not: Unused index'ler opsiyonel olarak kaldırılabilir
-- Bunlar veritabanı boyutunu küçültmek için kullanışlıdır
-- Ancak performansı etkileyebilir, dikkatli kullanılmalı

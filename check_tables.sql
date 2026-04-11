-- =====================================================
-- SUPABASE TABLO YAPISI KONTROL SORGUSU
-- =====================================================
-- Bu sorguyu Supabase SQL Editor'da çalıştırarak
-- hangi tablolarda hangi sütunlar var görebilirsiniz

-- Tüm tabloları ve sütunları listele
SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable
FROM 
    information_schema.columns
WHERE 
    table_schema = 'public'
    AND table_name IN (
        'categories',
        'shop_subscribers',
        'product_reviews',
        'campaigns',
        'coupons',
        'story_views',
        'follows',
        'conversations',
        'conversation_participants',
        'notification_tokens',
        'support_tickets',
        'app_settings',
        'posts',
        'post_likes',
        'post_comments',
        'post_saves',
        'profiles',
        'stories',
        'addresses',
        'shops',
        'products',
        'cart_items',
        'orders',
        'order_items',
        'notifications',
        'messages'
    )
ORDER BY 
    table_name, 
    ordinal_position;

-- =====================================================
-- ÖNEMLİ: Bu sorguyu çalıştırın ve sonucu bana gönderin
-- Hangi tablolarda "user_id" var, hangilerinde yok göreceğiz
-- =====================================================

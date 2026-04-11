-- ============================================================================
-- FIX get_pending_reviews TO CHECK BOTH shop_reviews AND product_reviews
-- Hem ürün hem satıcı değerlendirmesi yapıldığında listeden çıkar
-- ============================================================================

DROP FUNCTION IF EXISTS get_pending_reviews(UUID);

CREATE OR REPLACE FUNCTION get_pending_reviews(p_user_id UUID)
RETURNS TABLE (
    order_id UUID,
    shop_id UUID,
    shop_name TEXT,
    shop_logo TEXT,
    order_date TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    product_id UUID,
    product_name TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.id as order_id,
        o.shop_id,
        s.name as shop_name,
        s.logo_url as shop_logo,
        o.created_at as order_date,
        o.updated_at as delivered_at,
        (SELECT oi.product_id FROM order_items oi WHERE oi.order_id = o.id LIMIT 1) as product_id,
        (SELECT oi.product_name FROM order_items oi WHERE oi.order_id = o.id LIMIT 1) as product_name
    FROM orders o
    JOIN shops s ON s.id = o.shop_id
    -- Hem shop_reviews hem de product_reviews için kontrol
    LEFT JOIN shop_reviews sr ON sr.shop_id = o.shop_id AND sr.user_id = o.user_id AND sr.order_id = o.id
    LEFT JOIN product_reviews pr ON pr.order_id = o.id AND pr.user_id = o.user_id
    WHERE o.user_id = p_user_id
    AND o.status = 'delivered'
    -- Henüz HİÇBİR değerlendirme yapılmamış olmalı (hem satıcı hem ürün)
    AND sr.id IS NULL  
    AND pr.id IS NULL
    AND o.updated_at >= NOW() - INTERVAL '30 days'
    ORDER BY o.updated_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

SELECT '✅ get_pending_reviews fonksiyonu düzeltildi (hem ürün hem satıcı kontrolü)' AS result;

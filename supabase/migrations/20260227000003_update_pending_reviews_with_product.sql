-- ============================================================================
-- UPDATE get_pending_reviews TO INCLUDE PRODUCT INFO
-- Ürün bilgisi de döndür
-- ============================================================================

-- Önce mevcut fonksiyonu kaldır (return type değiştiği için gerekli)
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
    LEFT JOIN shop_reviews sr ON sr.shop_id = o.shop_id AND sr.user_id = o.user_id AND sr.order_id = o.id
    WHERE o.user_id = p_user_id
    AND o.status = 'delivered'
    AND sr.id IS NULL  -- Henüz değerlendirilmemiş
    AND o.updated_at >= NOW() - INTERVAL '30 days' -- Son 30 gün içinde teslim edilenler
    ORDER BY o.updated_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- product_reviews tablosuna order_id sütunu ekle (yoksa)
ALTER TABLE public.product_reviews ADD COLUMN IF NOT EXISTS order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_product_reviews_order_id ON public.product_reviews(order_id);

SELECT '✅ get_pending_reviews fonksiyonu güncellendi (ürün bilgisi eklendi)' AS result;

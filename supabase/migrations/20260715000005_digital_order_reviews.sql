-- Dijital ürün (SMM) siparişleri "orders" tablosuyla ilişkili değil, bu yüzden
-- get_pending_reviews sadece fiziksel siparişleri görüyordu. Tamamlanan
-- (completed) dijital siparişler için de ürün/satıcı değerlendirmesi açılıyor.

ALTER TABLE public.shop_reviews ADD COLUMN IF NOT EXISTS digital_order_id UUID REFERENCES public.digital_orders(id) ON DELETE SET NULL;
ALTER TABLE public.product_reviews ADD COLUMN IF NOT EXISTS digital_order_id UUID REFERENCES public.digital_orders(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_shop_reviews_unique_digital_order
ON public.shop_reviews(shop_id, user_id, digital_order_id)
WHERE digital_order_id IS NOT NULL;

DROP FUNCTION IF EXISTS get_pending_reviews(UUID);

CREATE OR REPLACE FUNCTION get_pending_reviews(p_user_id UUID)
RETURNS TABLE (
    order_id UUID,
    digital_order_id UUID,
    is_digital BOOLEAN,
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
    -- Fiziksel siparişler
    SELECT
        o.id as order_id,
        NULL::UUID as digital_order_id,
        FALSE as is_digital,
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
    LEFT JOIN product_reviews pr ON pr.order_id = o.id AND pr.user_id = o.user_id
    WHERE o.user_id = p_user_id
    AND o.status = 'delivered'
    AND sr.id IS NULL
    AND pr.id IS NULL
    AND o.updated_at >= NOW() - INTERVAL '30 days'

    UNION ALL

    -- Tamamlanmış dijital (SMM) siparişler
    SELECT
        NULL::UUID as order_id,
        d.id as digital_order_id,
        TRUE as is_digital,
        p.shop_id,
        s.name as shop_name,
        s.logo_url as shop_logo,
        d.created_at as order_date,
        d.last_checked_at as delivered_at,
        d.product_id,
        p.name as product_name
    FROM digital_orders d
    JOIN products p ON p.id = d.product_id
    JOIN shops s ON s.id = p.shop_id
    LEFT JOIN shop_reviews sr ON sr.shop_id = p.shop_id AND sr.user_id = d.user_id AND sr.digital_order_id = d.id
    LEFT JOIN product_reviews pr ON pr.digital_order_id = d.id AND pr.user_id = d.user_id
    WHERE d.user_id = p_user_id
    AND d.status = 'completed'
    AND sr.id IS NULL
    AND pr.id IS NULL
    AND d.created_at >= NOW() - INTERVAL '30 days'

    ORDER BY delivered_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

SELECT '✅ get_pending_reviews tamamlanmış dijital siparişleri de içeriyor' AS result;

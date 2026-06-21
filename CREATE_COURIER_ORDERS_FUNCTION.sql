-- ============================================================================
-- KURYELER İÇİN ATANABİLİR SİPARİŞLER FONKSİYONU
-- ============================================================================

CREATE OR REPLACE FUNCTION get_available_orders_for_courier(p_courier_id UUID)
RETURNS TABLE (
    id UUID,
    total NUMERIC,
    delivery_address_text TEXT,
    customer_phone TEXT,
    created_at TIMESTAMPTZ,
    shop_id UUID,
    status TEXT,
    shop_name TEXT,
    shop_has_own_courier BOOLEAN,
    order_items_json JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.id,
        o.total,
        o.delivery_address_text,
        o.customer_phone,
        o.created_at,
        o.shop_id,
        o.status,
        s.name as shop_name,
        s.has_own_courier as shop_has_own_courier,
        (
            SELECT jsonb_agg(jsonb_build_object(
                'quantity', oi.quantity,
                'product_name', oi.product_name
            ))
            FROM order_items oi
            WHERE oi.order_id = o.id
        ) as order_items_json
    FROM orders o
    JOIN shops s ON o.shop_id = s.id
    WHERE o.status IN ('confirmed', 'preparing', 'ready')
    AND (s.has_own_courier IS NULL OR s.has_own_courier = false)
    AND NOT EXISTS (
        SELECT 1 FROM courier_assignments ca
        WHERE ca.order_id = o.id
        AND ca.status IN ('assigned', 'picked_up', 'on_the_way', 'delivered')
    )
    ORDER BY o.created_at ASC;
END;
$$;

-- Doğrulama
SELECT 'RPC function created: get_available_orders_for_courier' as status;
-- ============================================================================
-- KURYENİN AKTİF SİPARİŞLERİ İÇİN FONKSİYON
-- ============================================================================

CREATE OR REPLACE FUNCTION get_courier_active_orders(p_courier_id UUID)
RETURNS TABLE (
    assignment_id UUID,
    assignment_status TEXT,
    fee_amount NUMERIC,
    assigned_at TIMESTAMPTZ,
    order_id UUID,
    order_total NUMERIC,
    order_status TEXT,
    delivery_address_text TEXT,
    customer_phone TEXT,
    created_at TIMESTAMPTZ,
    shop_name TEXT,
    order_items_json JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ca.id as assignment_id,
        ca.status as assignment_status,
        ca.fee_amount,
        ca.assigned_at,
        o.id as order_id,
        o.total as order_total,
        o.status as order_status,
        o.delivery_address_text,
        o.customer_phone,
        o.created_at,
        s.name as shop_name,
        (
            SELECT jsonb_agg(jsonb_build_object(
                'quantity', oi.quantity,
                'product_name', oi.product_name
            ))
            FROM order_items oi
            WHERE oi.order_id = o.id
        ) as order_items_json
    FROM courier_assignments ca
    JOIN orders o ON ca.order_id = o.id
    JOIN shops s ON o.shop_id = s.id
    WHERE ca.courier_id = p_courier_id
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way', 'delivered')
    ORDER BY ca.assigned_at DESC;
END;
$$;

-- Doğrulama
SELECT 'RPC function created: get_courier_active_orders' as status;
-- -----------------------------------------------------------------------------
-- BOLUM 7: Komisyon view'lari (kaynak: 20260131000002_commission_system.sql)
-- v_debt_orders ve v_admin_commission_dashboard uygulanmamisti.
-- Underlying orders kolonlari (admin_commission, commission_status,
-- commission_debt, admin_delivery_fee, order_number_int) mevcut RPC'ler
-- (get_seller_commission_summary vb.) tarafindan kullanildigi icin vardir.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_debt_orders AS
SELECT
    o.id,
    o.order_number_int,
    o.shop_id,
    s.name as shop_name,
    s.owner_id,
    o.subtotal,
    o.admin_commission,
    o.commission_debt,
    o.payment_method,
    o.status,
    o.created_at
FROM public.orders o
JOIN public.shops s ON s.id = o.shop_id
WHERE o.commission_status = 'debt'
  AND o.status != 'cancelled'
ORDER BY o.created_at DESC;

COMMENT ON VIEW public.v_debt_orders IS 'Borclu siparisler listesi (commission_status=debt)';

CREATE OR REPLACE VIEW public.v_admin_commission_dashboard AS
SELECT
    DATE(o.created_at) as date,
    COUNT(*) as order_count,
    SUM(o.subtotal) as total_sales,
    SUM(o.admin_commission) as total_commission,
    SUM(CASE WHEN o.commission_status = 'collected' THEN o.admin_commission ELSE 0 END) as collected_commission,
    SUM(CASE WHEN o.commission_status = 'debt' THEN o.admin_commission ELSE 0 END) as debt_commission,
    SUM(o.admin_delivery_fee) as total_delivery_fee,
    SUM(o.admin_commission + o.admin_delivery_fee) as total_admin_revenue
FROM public.orders o
WHERE o.status != 'cancelled'
GROUP BY DATE(o.created_at)
ORDER BY date DESC;

COMMENT ON VIEW public.v_admin_commission_dashboard IS 'Admin komisyon dashboard verileri';

-- View'lari admin/servis okuyabilsin. Komisyon verisi finansal oldugu icin
-- authenticated'a yalniz admin erisebilir; service_role tam erisir.
GRANT SELECT ON public.v_debt_orders TO authenticated, service_role;
GRANT SELECT ON public.v_admin_commission_dashboard TO authenticated, service_role;

-- =============================================================================
-- get_seller_earnings Edge Function'ı için DB-tarafı aggregate RPC.
-- PostgREST SUM/COUNT desteklemediği için özet, JS tarafında tüm satır
-- geçmişini çekip toplanmak yerine DB'de tek sorguda hesaplan��r.
-- Satıcı geçmişi büyüse bile network payload ve memory sabit kalır.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_seller_earnings_summary(p_seller_id uuid)
RETURNS TABLE(
  total_orders bigint,
  total_gross numeric,
  total_commission numeric,
  total_net numeric,
  pending_amount numeric,
  available_amount numeric,
  withdrawn_amount numeric
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    count(*)::bigint AS total_orders,
    COALESCE(sum(gross_amount), 0)     AS total_gross,
    COALESCE(sum(commission_amount), 0) AS total_commission,
    COALESCE(sum(net_amount), 0)        AS total_net,
    COALESCE(sum(net_amount) FILTER (WHERE status = 'pending'), 0)   AS pending_amount,
    COALESCE(sum(net_amount) FILTER (WHERE status = 'available'), 0) AS available_amount,
    COALESCE(sum(net_amount) FILTER (WHERE status = 'withdrawn'), 0) AS withdrawn_amount
  FROM public.seller_earnings
  WHERE seller_id = p_seller_id
    -- Defense-in-depth: yalnızca kendi özeti veya admin.
    AND (
      p_seller_id = (SELECT auth.uid())
      OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = (SELECT auth.uid()) AND role = 'admin'
      )
    );
$$;

GRANT EXECUTE ON FUNCTION public.get_seller_earnings_summary(uuid) TO authenticated;

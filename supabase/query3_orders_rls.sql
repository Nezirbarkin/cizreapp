-- =====================================================
-- QUERY 3: ORDERS RLS POLICY'LERİ
-- Bu sorguyu SQL Editor'da çalıştırıp sonucu gönderin
-- =====================================================
SELECT 
  pol.polname AS policy_name,
  pol.polcmd AS command,
  pg_get_expr(pol.polqual, pol.polrelid) AS using_expr
FROM pg_policy pol
WHERE pol.polrelid = 'public.orders'::regclass;

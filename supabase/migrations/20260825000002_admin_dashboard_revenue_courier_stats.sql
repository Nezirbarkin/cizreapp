-- ============================================================================
-- 20260825000002_admin_dashboard_revenue_courier_stats.sql
-- ----------------------------------------------------------------------------
-- Sorun: Admin dashboard ana sayfası (_part_dashboard.dart) gelir/ciro ve
-- kurye durumu göstermiyordu; bu veriler sadece ayrı sekmelere (Siparişler,
-- Kurye Yönetimi) girildiğinde görülebiliyordu. admin_dashboard_counts()
-- RPC'si (20260804000001) sadece basit count(*) sayaçları döndürüyordu.
--
-- Çözüm: admin_dashboard_counts() RPC'sinin döndürdüğü sütun kümesini
-- genişlet: toplam gelir, toplam admin komisyonu, dijital sipariş geliri,
-- toplam/çevrimiçi kurye sayısı. RETURNS TABLE imzası değiştiği için
-- fonksiyon DROP + CREATE ile yeniden oluşturuluyor (CREATE OR REPLACE
-- çıktı sütunlarını değiştiremez).
-- ============================================================================

begin;

DROP FUNCTION IF EXISTS public.admin_dashboard_counts();

CREATE FUNCTION public.admin_dashboard_counts()
RETURNS TABLE (
  total_users bigint,
  total_posts bigint,
  total_products bigint,
  total_orders bigint,
  total_reports bigint,
  unanswered_complaints bigint,
  unanswered_tickets bigint,
  total_revenue numeric,
  total_admin_commission numeric,
  total_digital_orders bigint,
  total_digital_revenue numeric,
  total_couriers bigint,
  online_couriers bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_dashboard_counts: not admin'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*) FROM public.profiles),
    (SELECT count(*) FROM public.posts),
    (SELECT count(*) FROM public.products),
    (SELECT count(*) FROM public.orders),
    (SELECT count(*) FROM public.user_reports),
    (SELECT count(*) FROM public.user_reports
       WHERE status IN ('pending','reviewing'))
      + COALESCE((SELECT count(*) FROM public.post_reports
                   WHERE status IN ('pending','reviewing')), 0),
    (SELECT count(*) FROM public.support_tickets
       WHERE status = 'open'),
    -- Toplam gelir: iptal edilmemiş siparişlerin brüt tutarı.
    -- Legacy 'total' kolonu boşsa 'total_amount' fallback (bkz.
    -- 20260708000000_FIX_SELLER_EARNINGS_TRIGGER.sql ile aynı desen).
    (SELECT COALESCE(SUM(COALESCE(NULLIF(o.total, 0), o.total_amount, 0)), 0)
       FROM public.orders o WHERE o.status <> 'cancelled'),
    (SELECT COALESCE(SUM(o.admin_commission), 0)
       FROM public.orders o WHERE o.status <> 'cancelled'),
    (SELECT count(*) FROM public.digital_orders),
    (SELECT COALESCE(SUM(d.total_price), 0)
       FROM public.digital_orders d
       WHERE d.status NOT IN ('canceled', 'refunded', 'failed')),
    (SELECT count(*) FROM public.profiles WHERE role = 'courier'::public.user_role),
    (SELECT count(*) FROM public.profiles
       WHERE role = 'courier'::public.user_role AND is_online = true);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_counts()
  TO authenticated, service_role;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_dashboard_counts'
  ) THEN
    RAISE EXCEPTION 'admin_dashboard_counts RPC bulunamadı';
  END IF;

  RAISE NOTICE '✅ 20260825000002 — admin_dashboard_counts gelir/kurye alanlarıyla genişletildi';
END $$;

NOTIFY pgrst, 'reload schema';

commit;

-- =============================================================================
-- Admin satıcı bilgileri: telefon / e-posta / adres / konum / IBAN
--
-- SORUN: Admin, satıcının cep telefonuna hiçbir ekrandan ulaşamıyordu.
--   * Satıcı telefonu shops.phone'da tutulur (dükkan açarken zorunlu,
--     20260928000010 guard_shop_contact_info). Admin ekranları ise sahibin
--     profiles.phone'unu okuyordu — canlıda 12 satıcının 12'sinde boş.
--   * admin_shops_page dükkanın phone/email/address/latitude/longitude/iban/
--     bank_name/account_holder_name alanlarını hiç döndürmüyordu; kart ve
--     "Dükkan Detayı" penceresi yalnız sahip adı + e-postası gösterebiliyordu.
--   * admin_user_detail yalnız profiles.phone döndürüyordu (satıcıda boş).
--
-- ÇÖZÜM (yalnız ekleme; mevcut anahtarlar ve hesaplar aynı):
--   * admin_shops_page satırına dükkanın iletişim + ödeme alanları ve
--     profiles nesnesine sahibin telefonu eklendi; arama telefonla da bulur.
--   * admin_user_detail'e shop_id + shop_phone eklendi.
--   Her ikisi de DEFINER + private.current_user_is_admin() kapısında kalır.
--
-- Gövdeler canlı tanımdan türetildi; yalnız "2026-10-28" işaretli satırlar yeni.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_shops_page(p_search text DEFAULT NULL::text, p_filter text DEFAULT NULL::text, p_sort text DEFAULT 'default'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_q      text := NULLIF(btrim(COALESCE(p_search, '')), '');
  v_filter text := CASE
                     WHEN p_filter IN ('pending', 'active', 'passive', 'pinned',
                                       'verified', 'admin_courier', 'overridden')
                     THEN p_filter
                   END;
  v_sort   text := COALESCE(p_sort, 'default');
  v_fee    double precision;
  v_res    jsonb;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_shops_page: not admin' USING ERRCODE = '42501';
  END IF;

  -- Kuryesi olmayan dükkanın teslimat başı kurye ücreti (eski _getCourierFee).
  SELECT cs.fee_per_delivery INTO v_fee
    FROM public.courier_settings cs
   ORDER BY cs.updated_at DESC
   LIMIT 1;
  v_fee := COALESCE(v_fee, 15);

  WITH ord AS (
    SELECT o.shop_id,
           count(*) AS total_orders,
           count(*) FILTER (WHERE o.status::text = 'delivered') AS delivered_orders,
           count(*) FILTER (WHERE o.status::text = 'cancelled') AS cancelled_orders,
           COALESCE(sum(o.total) FILTER (WHERE o.status::text = 'delivered'), 0)
             AS total_earnings,
           COALESCE(sum(o.total) FILTER (
             WHERE o.status::text = 'delivered'
               AND o.created_at > now() - interval '7 days'), 0) AS weekly_earnings,
           COALESCE(sum(o.total) FILTER (
             WHERE o.status::text = 'delivered'
               AND o.created_at > now() - interval '30 days'), 0) AS monthly_earnings
      FROM public.orders o
     GROUP BY o.shop_id
  ),
  prod AS (
    SELECT p.shop_id, count(*) AS product_count
      FROM public.products p
     GROUP BY p.shop_id
  ),
  base AS (
    SELECT s.id, s.name, s.slug, s.description, s.logo_url, s.category_id,
           s.owner_id, s.commission_rate, s.is_verified, s.is_approved,
           s.is_active, s.is_pinned, s.has_own_courier, s.delivery_fee,
           s.scheduled_orders_enabled, s.scheduled_orders_admin_blocked,
           s.min_order_amount, s.delivery_time, s.pre_override_delivery_fee,
           s.pre_override_min_order_amount, s.pre_override_delivery_time,
           s.admin_pricing_override_at, s.admin_pricing_override_note,
           s.created_at, s.admin_credit, s.commission_debt,
           s.total_collected_cash, s.total_paid, s.cash_payment_revenue,
           s.online_payment_revenue,
           -- 2026-10-28: satıcının iletişim + ödeme bilgileri. Satıcı telefonu
           -- shops.phone'da (dükkan açarken zorunlu, guard_shop_contact_info);
           -- sahibin profiles.phone'u neredeyse hep boş.
           s.phone, s.email, s.address, s.latitude, s.longitude,
           s.iban, s.bank_name,
           COALESCE(NULLIF(btrim(s.account_holder_name), ''), s.account_holder)
             AS account_holder_name,
           -- Görev 4.5: ana kategori adı/ikonu ve yönetici kilidi
           c.name AS category_name,
           c.icon AS category_icon,
           (cl.shop_id IS NOT NULL) AS category_locked,
           cl.note AS category_lock_note,
           CASE WHEN pf.id IS NULL THEN NULL
                ELSE jsonb_build_object(
                       'id', pf.id,
                       'username', pf.username,
                       'full_name', pf.full_name,
                       'avatar_url', pf.avatar_url,
                       'email', pf.email,
                       'phone', pf.phone)
           END AS profiles,
           COALESCE(pr.product_count, 0) AS product_count,
           COALESCE(od.total_orders, 0) AS total_orders,
           COALESCE(od.delivered_orders, 0) AS delivered_orders,
           COALESCE(od.total_orders, 0) - COALESCE(od.delivered_orders, 0)
             - COALESCE(od.cancelled_orders, 0) AS pending_orders,
           COALESCE(od.cancelled_orders, 0) AS cancelled_orders,
           COALESCE(od.total_earnings, 0) AS total_earnings,
           COALESCE(od.weekly_earnings, 0) AS weekly_earnings,
           COALESCE(od.monthly_earnings, 0) AS monthly_earnings,
           COALESCE(od.total_earnings, 0) * COALESCE(s.commission_rate, 10) / 100
             AS admin_commission_total,
           CASE WHEN NOT COALESCE(s.has_own_courier, true)
                THEN COALESCE(od.delivered_orders, 0) * v_fee
                ELSE 0
           END AS courier_deduction
      FROM public.shops s
      LEFT JOIN public.profiles pf ON pf.id = s.owner_id
      LEFT JOIN public.categories c ON c.id = s.category_id
      LEFT JOIN public.shop_category_locks cl ON cl.shop_id = s.id
      LEFT JOIN ord od ON od.shop_id = s.id
      LEFT JOIN prod pr ON pr.shop_id = s.id
  ),
  full_rows AS (
    SELECT b.*,
           b.total_earnings - b.admin_commission_total - b.courier_deduction
             AS net_earnings,
           (b.pre_override_delivery_fee IS NOT NULL
            OR b.pre_override_min_order_amount IS NOT NULL
            OR b.pre_override_delivery_time IS NOT NULL) AS is_overridden
      FROM base b
  ),
  f AS (
    SELECT r.*
      FROM full_rows r
     WHERE (v_q IS NULL
            OR r.name ILIKE '%' || v_q || '%'
            OR r.slug ILIKE '%' || v_q || '%'
            OR r.description ILIKE '%' || v_q || '%'
            OR r.profiles->>'full_name' ILIKE '%' || v_q || '%'
            OR r.profiles->>'username' ILIKE '%' || v_q || '%'
            OR r.profiles->>'email' ILIKE '%' || v_q || '%'
            OR r.phone ILIKE '%' || v_q || '%'
            OR r.profiles->>'phone' ILIKE '%' || v_q || '%'
            OR r.category_name ILIKE '%' || v_q || '%')
       AND (v_filter IS NULL
            OR (v_filter = 'pending'       AND NOT COALESCE(r.is_approved, false))
            OR (v_filter = 'active'        AND COALESCE(r.is_active, true))
            OR (v_filter = 'passive'       AND NOT COALESCE(r.is_active, true))
            OR (v_filter = 'pinned'        AND COALESCE(r.is_pinned, false))
            OR (v_filter = 'verified'      AND COALESCE(r.is_verified, false))
            OR (v_filter = 'admin_courier' AND NOT COALESCE(r.has_own_courier, false))
            OR (v_filter = 'overridden'    AND r.is_overridden))
  ),
  ranked AS (
    SELECT f.*,
           row_number() OVER (
             ORDER BY
               CASE WHEN v_sort = 'earnings' THEN f.total_earnings END DESC NULLS LAST,
               CASE WHEN v_sort = 'orders'   THEN f.total_orders   END DESC NULLS LAST,
               CASE WHEN v_sort = 'newest'   THEN f.created_at     END DESC NULLS LAST,
               CASE WHEN v_sort NOT IN ('name', 'earnings', 'orders', 'newest')
                    THEN CASE WHEN COALESCE(f.is_pinned, false) THEN 0 ELSE 1 END
               END ASC,
               lower(COALESCE(f.name, '')) ASC,
               f.id
           ) AS rn
      FROM f
  )
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM f),
    'rows', COALESCE((
      SELECT jsonb_agg(to_jsonb(pg) - 'rn' - 'is_overridden' ORDER BY pg.rn)
        FROM (SELECT * FROM ranked ORDER BY rn LIMIT v_limit OFFSET v_offset) pg
    ), '[]'::jsonb),
    'summary', (
      SELECT jsonb_build_object(
        'total',         count(*),
        'pending',       count(*) FILTER (WHERE NOT COALESCE(a.is_approved, false)),
        'active',        count(*) FILTER (WHERE COALESCE(a.is_active, true)),
        'passive',       count(*) FILTER (WHERE NOT COALESCE(a.is_active, true)),
        'pinned',        count(*) FILTER (WHERE COALESCE(a.is_pinned, false)),
        'verified',      count(*) FILTER (WHERE COALESCE(a.is_verified, false)),
        'admin_courier', count(*) FILTER (WHERE NOT COALESCE(a.has_own_courier, false)),
        'overridden',    count(*) FILTER (WHERE a.is_overridden),
        'revenue',       COALESCE(sum(a.total_earnings), 0),
        'commission',    COALESCE(sum(a.admin_commission_total), 0)
      )
        FROM full_rows a
    )
  ) INTO v_res;

  RETURN v_res;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_user_detail(p_target uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_res jsonb;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_user_detail: not admin' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'full_name', p.full_name,
    'avatar_url', p.avatar_url,
    'cover_url', p.cover_url,
    'bio', p.bio,
    'location', p.location,
    'website', p.website,
    'gender', p.gender,
    'role', p.role::text,
    'status', p.status::text,
    'email', p.email,
    'phone', p.phone,
    'is_suspicious', COALESCE(p.is_suspicious, false),
    'suspicious_reason', p.suspicious_reason,
    'is_verified', COALESCE(p.is_verified, false),
    'platform', p.platform,
    'created_at', p.created_at,
    'last_seen', p.last_seen,
    'is_online', (p.last_seen >= now() - interval '5 minutes'),
    'provider', u.raw_app_meta_data->>'provider',
    'last_sign_in_at', u.last_sign_in_at,
    'email_confirmed_at', u.email_confirmed_at,
    'banned_until', u.banned_until,
    'posts_count', (SELECT count(*) FROM public.posts x WHERE x.user_id = p.id),
    'followers_count', (SELECT count(*) FROM public.follows x WHERE x.following_id = p.id),
    'following_count', (SELECT count(*) FROM public.follows x WHERE x.follower_id = p.id),
    'orders_count', (SELECT count(*) FROM public.orders x WHERE x.user_id = p.id),
    'digital_orders_count', (SELECT count(*) FROM public.digital_orders x WHERE x.user_id = p.id),
    'activity_count', (SELECT count(*) FROM public.user_activity_logs x WHERE x.user_id = p.id),
    'balance', COALESCE((SELECT b.balance FROM public.user_balances b WHERE b.user_id = p.id), 0),
    'points', COALESCE((SELECT a.balance_points FROM public.user_point_accounts a WHERE a.user_id = p.id), 0),
    'shop_name', (SELECT s.name FROM public.shops s WHERE s.owner_id = p.id LIMIT 1),
    -- 2026-10-28: satıcının telefonu dükkanda tutulur (profiles.phone boş).
    'shop_id', (SELECT s.id FROM public.shops s WHERE s.owner_id = p.id LIMIT 1),
    'shop_phone', (SELECT s.phone FROM public.shops s WHERE s.owner_id = p.id LIMIT 1)
  )
  INTO v_res
  FROM public.profiles AS p
  LEFT JOIN auth.users AS u ON u.id = p.id
  WHERE p.id = p_target;

  IF v_res IS NULL THEN
    RAISE EXCEPTION 'admin_user_detail: user not found' USING ERRCODE = 'P0002';
  END IF;
  RETURN v_res;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_shops_page(text, text, text, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_shops_page(text, text, text, integer, integer)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_user_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_user_detail(uuid) TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';

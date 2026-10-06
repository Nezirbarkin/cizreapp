-- =============================================================================
-- Görev 4.5 — Admin: satıcının ana kategorisini değiştirme ve kilitleme
-- =============================================================================
--
-- Satıcı mağazasının ana kategorisini (`shops.category_id`) mağaza
-- ayarlarından seçer. Yönetici artık panelden doğrudan değiştirir:
--   * `admin_set_shop_category(shop, category, lock, note)` — DEFINER, yönetici
--     kontrolü, pasif kategoriye taşımaz, denetim günlüğüne yazar, kategori
--     değiştiyse satıcıya bildirim gönderir.
--   * İsteğe bağlı KİLİT: satıcı kategoriyi geri değiştiremez. Kilit ayrı
--     tablodadır (`shop_category_locks`) çünkü satıcı kendi mağaza satırını RLS
--     ile güncelleyebiliyor; kilit shops'ta olsaydı kendisi açardı. Koruma
--     INVOKER tetikleyicidir (DEFINER olsaydı current_user/yetki bağlamı yanlış
--     olurdu — bkz. etkisiz finans koruması).
--   * `admin_shops_page` satırlarına kategori adı/ikonu ve kilit eklendi;
--     arama kategori adıyla da eşleşir.

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Kilit tablosu: satıcı yalnız kendi mağazasının kilidini OKUR, kimse yazamaz
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shop_category_locks (
  shop_id   uuid PRIMARY KEY REFERENCES public.shops(id) ON DELETE CASCADE,
  locked_by uuid,
  note      text CHECK (note IS NULL OR char_length(note) <= 300),
  locked_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.shop_category_locks IS
  'Görev 4.5: yönetici ana kategoriyi kilitlediyse satıcı değiştiremez. Yalnız admin_set_shop_category yazar.';

ALTER TABLE public.shop_category_locks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.shop_category_locks FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.shop_category_locks TO authenticated;

DROP POLICY IF EXISTS shop_category_locks_read ON public.shop_category_locks;
CREATE POLICY shop_category_locks_read ON public.shop_category_locks
  FOR SELECT TO authenticated
  USING (
    public.auth_is_admin()
    OR EXISTS (SELECT 1 FROM public.shops s
                WHERE s.id = shop_category_locks.shop_id AND s.owner_id = (SELECT auth.uid()))
  );

-- -----------------------------------------------------------------------------
-- 2) Koruma: kilitliyken ana kategoriyi yalnız yönetici/sistem değiştirir
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.guard_shop_category_lock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $fn$
BEGIN
  IF NEW.category_id IS NOT DISTINCT FROM OLD.category_id THEN
    RETURN NEW;
  END IF;
  IF auth.uid() IS NULL OR public.auth_is_admin() THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1 FROM public.shop_category_locks l WHERE l.shop_id = NEW.id) THEN
    RAISE EXCEPTION 'Ana kategori yönetim tarafından belirlendi'
      USING ERRCODE = 'P0001', HINT = 'SHOP_CATEGORY_LOCKED';
  END IF;
  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION private.guard_shop_category_lock() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_shops_guard_category_lock ON public.shops;
CREATE TRIGGER trg_shops_guard_category_lock
  BEFORE UPDATE OF category_id ON public.shops
  FOR EACH ROW EXECUTE FUNCTION private.guard_shop_category_lock();

-- -----------------------------------------------------------------------------
-- 3) Yönetici: ana kategoriyi değiştir / kilitle / kilidi aç
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_shop_category(
  p_shop_id uuid,
  p_category_id uuid,
  p_lock boolean DEFAULT true,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_shop record;
  v_old_name text;
  v_new public.categories%ROWTYPE;
  v_note text := NULLIF(btrim(left(COALESCE(p_note, ''), 300)), '');
  v_lock boolean := COALESCE(p_lock, false);
  v_was_locked boolean;
  v_changed boolean;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  SELECT s.id, s.name, s.owner_id, s.category_id INTO v_shop
    FROM public.shops s WHERE s.id = p_shop_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mağaza bulunamadı' USING ERRCODE = 'P0001', HINT = 'SHOP_NOT_FOUND';
  END IF;
  SELECT * INTO v_new FROM public.categories c WHERE c.id = p_category_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kategori bulunamadı' USING ERRCODE = 'P0001', HINT = 'CATEGORY_NOT_FOUND';
  END IF;
  -- Pasif kategorideki mağaza market ekranında görünmez; önce kategori açılmalı.
  IF NOT COALESCE(v_new.is_active, true) THEN
    RAISE EXCEPTION 'Kategori pasif' USING ERRCODE = 'P0001', HINT = 'CATEGORY_INACTIVE';
  END IF;

  SELECT c.name INTO v_old_name FROM public.categories c WHERE c.id = v_shop.category_id;
  v_was_locked := EXISTS (SELECT 1 FROM public.shop_category_locks l WHERE l.shop_id = p_shop_id);
  v_changed := v_shop.category_id IS DISTINCT FROM p_category_id;

  IF v_changed THEN
    UPDATE public.shops SET category_id = p_category_id WHERE id = p_shop_id;
  END IF;

  IF v_lock THEN
    INSERT INTO public.shop_category_locks (shop_id, locked_by, note, locked_at)
    VALUES (p_shop_id, auth.uid(), v_note, now())
    ON CONFLICT (shop_id) DO UPDATE
      SET locked_by = EXCLUDED.locked_by, note = EXCLUDED.note, locked_at = EXCLUDED.locked_at;
  ELSE
    DELETE FROM public.shop_category_locks WHERE shop_id = p_shop_id;
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, old_data, new_data)
  VALUES (auth.uid(), 'set_shop_category', 'shops', p_shop_id::text,
          jsonb_build_object('category_id', v_shop.category_id, 'category', v_old_name, 'locked', v_was_locked),
          jsonb_build_object('category_id', p_category_id, 'category', v_new.name, 'locked', v_lock, 'note', v_note));

  IF v_changed OR v_lock IS DISTINCT FROM v_was_locked THEN
    INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata, is_read, created_at)
    SELECT v_shop.owner_id, 'admin_notification',
           CASE WHEN v_changed THEN 'Mağaza kategorin güncellendi' ELSE 'Mağaza kategorin' END,
           CASE
             WHEN v_changed THEN
               format('%s mağazasının ana kategorisi yönetim tarafından "%s" olarak değiştirildi%s.%s',
                      v_shop.name, v_new.name, COALESCE(': ' || v_note, ''),
                      CASE WHEN v_lock THEN ' Kategoriyi artık yalnız yönetim değiştirebilir.' ELSE '' END)
             WHEN v_lock THEN
               format('%s mağazasının ana kategorisi ("%s") yönetim tarafından sabitlendi%s.',
                      v_shop.name, v_new.name, COALESCE(': ' || v_note, ''))
             ELSE
               format('%s mağazasının ana kategorisini artık yeniden kendin seçebilirsin.', v_shop.name)
           END,
           p_shop_id::text, 'shop',
           jsonb_build_object('source', 'shop_category', 'category_id', p_category_id),
           false, now()
     WHERE v_shop.owner_id IS NOT NULL;
  END IF;

  RETURN jsonb_build_object(
    'category_id', p_category_id,
    'category_name', v_new.name,
    'locked', v_lock,
    'changed', v_changed
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_set_shop_category(uuid, uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_shop_category(uuid, uuid, boolean, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) Admin > Dükkanlar: satırlara kategori adı/ikonu ve kilit (1.3 tanımı + alanlar)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_shops_page(
  p_search text    DEFAULT NULL,
  p_filter text    DEFAULT NULL,  -- pending | active | passive | pinned | verified | admin_courier | overridden
  p_sort   text    DEFAULT 'default', -- default | name | earnings | orders | newest
  p_limit  integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
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
           s.min_order_amount, s.delivery_time, s.pre_override_delivery_fee,
           s.pre_override_min_order_amount, s.pre_override_delivery_time,
           s.admin_pricing_override_at, s.admin_pricing_override_note,
           s.created_at, s.admin_credit, s.commission_debt,
           s.total_collected_cash, s.total_paid, s.cash_payment_revenue,
           s.online_payment_revenue,
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
                       'email', pf.email)
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
$$;

REVOKE ALL ON FUNCTION public.admin_shops_page(text, text, text, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_shops_page(text, text, text, integer, integer)
  TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

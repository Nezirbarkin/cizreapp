-- =============================================================================
-- PL/pgSQL LINTER: RUNTIME ERROR FIXES
-- =============================================================================
-- The live `supabase db lint --linked --level warning` report found functions
-- compiled against old table/enum definitions. This migration updates only the
-- broken public functions and preserves their existing signatures.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Sehirici/courier functions
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auth_sehirici_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = (SELECT auth.uid())
      AND (p.role::text = 'admin' OR COALESCE(p.is_admin, false))
  );
$$;

REVOKE EXECUTE ON FUNCTION public.auth_sehirici_is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_sehirici_is_admin() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_upsert_sehirici_driver(
  p_id uuid,
  p_profile_id uuid,
  p_license_number text,
  p_phone text,
  p_status text,
  p_assigned_line_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  INSERT INTO public.sehirici_drivers (
    id, profile_id, license_number, phone, assigned_line_id, is_on_duty
  )
  VALUES (
    COALESCE(p_id, gen_random_uuid()),
    p_profile_id,
    NULLIF(btrim(p_license_number), ''),
    NULLIF(btrim(p_phone), ''),
    p_assigned_line_id,
    COALESCE(NULLIF(p_status, ''), 'active') NOT IN ('inactive', 'disabled', 'off_duty')
  )
  ON CONFLICT (id) DO UPDATE SET
    profile_id = EXCLUDED.profile_id,
    license_number = EXCLUDED.license_number,
    phone = EXCLUDED.phone,
    assigned_line_id = EXCLUDED.assigned_line_id,
    is_on_duty = EXCLUDED.is_on_duty,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_upsert_sehirici_driver(uuid, uuid, text, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_upsert_sehirici_driver(uuid, uuid, text, text, text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_available_orders_for_courier(p_courier_id uuid)
RETURNS TABLE(
  id uuid,
  total numeric,
  delivery_address_text text,
  customer_phone text,
  created_at timestamptz,
  shop_id uuid,
  status text,
  shop_name text,
  shop_has_own_courier boolean,
  order_items_json jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_courier_id IS DISTINCT FROM (SELECT auth.uid())
     AND NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Yetkisiz kurye sorgusu';
  END IF;

  RETURN QUERY
  SELECT
    o.id,
    o.total,
    o.delivery_address_text,
    o.customer_phone,
    o.created_at,
    o.shop_id,
    o.status::text,
    s.name::text,
    s.has_own_courier,
    (
      SELECT jsonb_agg(jsonb_build_object(
        'quantity', oi.quantity,
        'product_name', oi.product_name
      ))
      FROM public.order_items AS oi
      WHERE oi.order_id = o.id
    )
  FROM public.orders AS o
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE o.status IN ('confirmed', 'preparing', 'ready')
    AND COALESCE(s.has_own_courier, false) = false
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_assignments AS ca
      WHERE ca.order_id = o.id
        AND ca.status IN ('assigned', 'picked_up', 'on_the_way', 'delivered')
    )
  ORDER BY o.created_at ASC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_available_orders_for_courier(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_available_orders_for_courier(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_courier_active_orders(p_courier_id uuid)
RETURNS TABLE(
  assignment_id uuid,
  assignment_status text,
  fee_amount numeric,
  assigned_at timestamptz,
  order_id uuid,
  order_total numeric,
  order_status text,
  delivery_address_text text,
  customer_phone text,
  created_at timestamptz,
  shop_name text,
  order_items_json jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_courier_id IS DISTINCT FROM (SELECT auth.uid())
     AND NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Yetkisiz kurye sorgusu';
  END IF;

  RETURN QUERY
  SELECT
    ca.id,
    ca.status::text,
    ca.fee_amount::numeric,
    ca.assigned_at,
    o.id,
    o.total,
    o.status::text,
    o.delivery_address_text,
    o.customer_phone,
    o.created_at,
    s.name::text,
    (
      SELECT jsonb_agg(jsonb_build_object(
        'quantity', oi.quantity,
        'product_name', oi.product_name
      ))
      FROM public.order_items AS oi
      WHERE oi.order_id = o.id
    )
  FROM public.courier_assignments AS ca
  JOIN public.orders AS o ON o.id = ca.order_id
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE ca.courier_id = p_courier_id
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way', 'delivered')
  ORDER BY ca.assigned_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_courier_active_orders(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_courier_active_orders(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 2) Group/admin functions compiled against removed columns
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_all_join_requests()
RETURNS TABLE(
  request_id uuid,
  group_id uuid,
  user_id uuid,
  message text,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  reviewed_at timestamptz,
  group_name text,
  group_avatar_url text,
  group_is_private boolean,
  user_full_name text,
  user_avatar_url text,
  user_username text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
  END IF;

  RETURN QUERY
  SELECT
    jr.id,
    jr.group_id,
    jr.user_id,
    jr.message,
    jr.status,
    jr.created_at,
    jr.updated_at,
    jr.updated_at AS reviewed_at,
    g.name,
    g.avatar_url,
    g.is_private,
    p.full_name,
    p.avatar_url,
    p.username
  FROM public.group_join_requests AS jr
  LEFT JOIN public.groups AS g ON g.id = jr.group_id
  LEFT JOIN public.profiles AS p ON p.id = jr.user_id
  WHERE jr.status = 'pending'
  ORDER BY jr.created_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_get_all_join_requests() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_all_join_requests() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_approve_join_request(p_request_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id uuid;
  v_user_id uuid;
  v_count integer;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
  END IF;

  SELECT jr.group_id, jr.user_id
  INTO v_group_id, v_user_id
  FROM public.group_join_requests AS jr
  WHERE jr.id = p_request_id
    AND jr.status = 'pending'
  FOR UPDATE;

  IF v_group_id IS NULL THEN
    RETURN false;
  END IF;

  INSERT INTO public.group_members (group_id, user_id, role)
  VALUES (v_group_id, v_user_id, 'member')
  ON CONFLICT (group_id, user_id) DO NOTHING;

  UPDATE public.group_join_requests
  SET status = 'approved', updated_at = now()
  WHERE id = p_request_id;

  SELECT count(*) INTO v_count
  FROM public.group_members
  WHERE group_id = v_group_id;

  UPDATE public.groups
  SET member_count = v_count, updated_at = now()
  WHERE id = v_group_id;

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_approve_join_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_approve_join_request(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_reject_join_request(p_request_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_updated integer;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
  END IF;

  UPDATE public.group_join_requests
  SET status = 'rejected', updated_at = now()
  WHERE id = p_request_id
    AND status = 'pending';

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_reject_join_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reject_join_request(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_post(post_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted_id uuid;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler gönderi silebilir';
  END IF;

  DELETE FROM public.post_likes AS pl WHERE pl.post_id = admin_delete_post.post_id;
  DELETE FROM public.post_views AS pv WHERE pv.post_id = admin_delete_post.post_id;
  DELETE FROM public.post_comments AS pc WHERE pc.post_id = admin_delete_post.post_id;
  DELETE FROM public.post_saves AS ps WHERE ps.post_id = admin_delete_post.post_id;
  DELETE FROM public.post_favorites AS pf WHERE pf.post_id = admin_delete_post.post_id;
  DELETE FROM public.post_reports AS pr WHERE pr.reported_post_id = admin_delete_post.post_id;

  DELETE FROM public.posts AS p
  WHERE p.id = admin_delete_post.post_id
  RETURNING p.id INTO v_deleted_id;

  RETURN jsonb_build_object(
    'success', v_deleted_id IS NOT NULL,
    'message', CASE WHEN v_deleted_id IS NOT NULL
      THEN 'Gönderi başarıyla silindi'
      ELSE 'Gönderi bulunamadı'
    END,
    'post_id', admin_delete_post.post_id
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_delete_post(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_post(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3) Favorite helpers: keep empty search_path, fully qualify every relation.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_product_favorite_count(p_product_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT count(*)::integer
  FROM public.product_favorites AS pf
  WHERE pf.product_id = p_product_id;
$$;

CREATE OR REPLACE FUNCTION public.is_product_favorited(p_user_id uuid, p_product_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.product_favorites AS pf
    WHERE pf.user_id = p_user_id
      AND pf.product_id = p_product_id
  );
$$;

CREATE OR REPLACE FUNCTION public.toggle_product_favorite(p_user_id uuid, p_product_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF p_user_id IS DISTINCT FROM (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Başka bir kullanıcı adına favori değiştirilemez';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.product_favorites AS pf
    WHERE pf.user_id = p_user_id
      AND pf.product_id = p_product_id
  ) THEN
    DELETE FROM public.product_favorites AS pf
    WHERE pf.user_id = p_user_id
      AND pf.product_id = p_product_id;
    RETURN false;
  END IF;

  INSERT INTO public.product_favorites (user_id, product_id)
  VALUES (p_user_id, p_product_id)
  ON CONFLICT (user_id, product_id) DO NOTHING;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_post_favorite_count(p_post_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT count(*)::integer
  FROM public.post_favorites AS pf
  WHERE pf.post_id = p_post_id;
$$;

CREATE OR REPLACE FUNCTION public.is_post_favorited(p_user_id uuid, p_post_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.post_favorites AS pf
    WHERE pf.user_id = p_user_id
      AND pf.post_id = p_post_id
  );
$$;

-- -----------------------------------------------------------------------------
-- 4) Remove an obsolete overload compiled against a former user preference
--    version of email_settings. The active global get_email_settings() remains.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_email_settings(uuid);

-- -----------------------------------------------------------------------------
-- 5) Qualify payment transaction columns that conflict with OUT parameter names.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.atomic_finalize_payment_transaction(
  p_transaction_id uuid,
  p_payment_id text,
  p_paid_price numeric,
  p_card_type text,
  p_card_association text,
  p_card_family text,
  p_card_bank_name text,
  p_last_four_digits text,
  p_fraud_status integer,
  p_status text,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL,
  p_error_group text DEFAULT NULL,
  p_callback_received_at timestamptz DEFAULT now(),
  p_merged_callback_data jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE(updated boolean, already_processed boolean, payment_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_current_status text;
  v_row_count integer;
BEGIN
  SELECT pt.payment_status
  INTO v_current_status
  FROM public.payment_transactions AS pt
  WHERE pt.id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, false, NULL::text;
    RETURN;
  END IF;

  IF v_current_status IS DISTINCT FROM 'pending' THEN
    RETURN QUERY SELECT false, true, v_current_status;
    RETURN;
  END IF;

  UPDATE public.payment_transactions AS pt
  SET payment_status = p_status,
      payment_id = p_payment_id,
      paid_price = p_paid_price,
      card_type = p_card_type,
      card_association = p_card_association,
      card_family = p_card_family,
      card_bank_name = p_card_bank_name,
      last_four_digits = p_last_four_digits,
      fraud_status = p_fraud_status,
      callback_received_at = p_callback_received_at,
      callback_data = COALESCE(pt.callback_data, '{}'::jsonb) || p_merged_callback_data,
      error_code = p_error_code,
      error_message = p_error_message,
      error_group = p_error_group,
      updated_at = now()
  WHERE pt.id = p_transaction_id
    AND pt.payment_status = 'pending';

  GET DIAGNOSTICS v_row_count = ROW_COUNT;

  IF v_row_count = 0 THEN
    RETURN QUERY SELECT false, true, v_current_status;
  ELSE
    RETURN QUERY SELECT true, false, p_status;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.atomic_finalize_payment_transaction(
  uuid, text, numeric, text, text, text, text, text, integer, text,
  text, text, text, timestamptz, jsonb
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atomic_finalize_payment_transaction(
  uuid, text, numeric, text, text, text, text, text, integer, text,
  text, text, text, timestamptz, jsonb
) TO service_role;

-- -----------------------------------------------------------------------------
-- 6) Account deletion: use current table names and rely on FK restrictions to
--    fail atomically if a newly-added dependent table needs explicit handling.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_account_with_code(p_confirmation_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_stored_code text;
  v_expires_at timestamptz;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT adc.code, adc.expires_at
  INTO v_stored_code, v_expires_at
  FROM public.account_deletion_codes AS adc
  WHERE adc.user_id = v_user_id
  FOR UPDATE;

  IF v_stored_code IS NULL THEN
    RAISE EXCEPTION 'Onay kodu bulunamadı';
  END IF;
  IF now() > v_expires_at THEN
    RAISE EXCEPTION 'Onay kodu süresi dolmuş';
  END IF;
  IF v_stored_code IS DISTINCT FROM p_confirmation_code THEN
    RAISE EXCEPTION 'Geçersiz onay kodu';
  END IF;

  DELETE FROM public.account_deletion_codes AS adc WHERE adc.user_id = v_user_id;
  DELETE FROM public.post_comments AS pc WHERE pc.user_id = v_user_id;
  DELETE FROM public.post_likes AS pl WHERE pl.user_id = v_user_id;
  DELETE FROM public.post_saves AS ps WHERE ps.user_id = v_user_id;
  DELETE FROM public.post_favorites AS pf WHERE pf.user_id = v_user_id;
  DELETE FROM public.product_favorites AS pf WHERE pf.user_id = v_user_id;
  DELETE FROM public.stories AS s WHERE s.user_id = v_user_id;
  DELETE FROM public.posts AS p WHERE p.user_id = v_user_id;
  DELETE FROM public.profiles AS p WHERE p.id = v_user_id;
  DELETE FROM auth.users AS u WHERE u.id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Hesabınız başarıyla silindi'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_account_with_code(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_account_with_code(text) TO authenticated;

-- =============================================================================
-- End of migration
-- =============================================================================

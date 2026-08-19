-- =============================================================================
-- Fix admin_set_user_role(): compare values with the same PostgreSQL type.
--
-- v_old_role is text because the profiles.role enum is selected into a text
-- variable. Comparing it with 'admin'::public.user_role fails with SQLSTATE
-- 42883 (operator does not exist: text = public.user_role).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_set_user_role(
  p_target_user_id uuid,
  p_new_role text,
  p_reason text DEFAULT NULL,
  p_request_id text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_old_role text;
  v_admin_count integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'admin_set_user_role: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_set_user_role: not admin'
      USING ERRCODE = '42501';
  END IF;

  IF p_new_role NOT IN ('customer','seller','admin','courier','driver','news') THEN
    RAISE EXCEPTION 'admin_set_user_role: invalid role %', p_new_role
      USING ERRCODE = '22023';
  END IF;

  SELECT p.role::text
  INTO v_old_role
  FROM public.profiles AS p
  WHERE p.id = p_target_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_set_user_role: target not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_old_role = p_new_role THEN
    RETURN v_old_role;
  END IF;

  -- Both operands are text. Enum comparisons against the table column remain
  -- explicitly typed below so PostgreSQL never has to infer mixed operators.
  IF v_old_role = 'admin' AND p_new_role <> 'admin' THEN
    SELECT count(*)
    INTO v_admin_count
    FROM public.profiles AS p
    WHERE p.role = 'admin'::public.user_role
      AND p.id <> p_target_user_id;

    IF v_admin_count = 0 THEN
      RAISE EXCEPTION 'admin_set_user_role: cannot demote last admin'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  UPDATE public.profiles AS p
  SET role = p_new_role::public.user_role,
      is_admin = (p_new_role = 'admin'),
      updated_at = NOW()
  WHERE p.id = p_target_user_id;

  INSERT INTO public.profile_role_change_audit
    (target_user_id, old_role, new_role, changed_by, reason, request_id)
  VALUES
    (p_target_user_id, v_old_role, p_new_role, v_uid, p_reason, p_request_id);

  RETURN p_new_role;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_user_role(uuid, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_role(uuid, text, text, text)
  TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

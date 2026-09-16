-- ============================================================================
-- admin_list_couriers: admin kurye listesine phone + email eklendi.
-- ----------------------------------------------------------------------------
-- Admin panelindeki kurye kartı zaten `courier['email']` okuyordu ama bu RPC
-- hiç email döndürmüyordu (kart hep boş görünüyordu) ve telefon hiç yoktu.
-- Admin'in kuryeye ulaşabilmesi için (bkz. "Gel Al" + iletişim bilgisi
-- görevi) her ikisi de eklendi. profiles üzerindeki email/phone sütun
-- grant'ları kısıtlı olduğu için (bkz. PENDING_RELEASE_20260908_revoke_profiles_pii)
-- bu veriye yalnızca SECURITY DEFINER RPC üzerinden, admin kontrolüyle erişiliyor.
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_list_couriers();

CREATE OR REPLACE FUNCTION public.admin_list_couriers()
RETURNS TABLE(
  id uuid,
  username text,
  full_name text,
  avatar_url text,
  is_online boolean,
  delivered_count integer,
  created_at timestamp with time zone,
  phone text,
  email text
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_list_couriers: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.full_name,
    p.avatar_url,
    p.is_online,
    p.delivered_count,
    p.created_at,
    p.phone,
    p.email
  FROM public.profiles p
  WHERE p.role = 'courier'::public.user_role
  ORDER BY p.created_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_couriers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_couriers()
  TO authenticated, service_role;

DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

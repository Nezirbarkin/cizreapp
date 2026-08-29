-- =============================================================================
-- 20260829000002_admin_user_role_counts.sql
--
-- Kok neden: Admin panelinde "Kullanicilar" sekmesindeki ozet kartlar
-- (Toplam / Admin / Satici / Kurye / Sofor / Haberci), admin_user_list_with_stats
-- RPC'sinin dondurdugu SINIRLI listeden (ORDER BY created_at DESC LIMIT 100)
-- client-side sayilarak hesaplaniyordu (bkz. _part_users.dart _buildUsersContent).
--
-- Profil sayisi 100'u astikca ve admin/kurye/haberci hesaplari erken
-- tarihte acildigi icin (kurulum hesaplari), "en yeni 100" penceresinin
-- disinda kaliyorlar ve kartlarda "0" gorunuyorlardi -- veri yokmus gibi
-- degil, sayfalanmis pencerenin disinda kaldiklari icin.
--
-- Kalici cozum: ozet sayilari, liste limitinden tamamen BAGIMSIZ, tum
-- profiles tablosu uzerinde GROUP BY role ile hesaplayan ayri bir RPC.
-- Boylece kullanici listesi sayfalanabilir kalirken ust kartlar her zaman
-- gercek toplami gosterir.
-- =============================================================================

begin;

CREATE OR REPLACE FUNCTION public.admin_user_role_counts()
RETURNS TABLE (
  role text,
  user_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_user_role_counts: not admin'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT COALESCE(p.role::text, 'customer') AS role, count(*)::bigint AS user_count
  FROM public.profiles p
  GROUP BY COALESCE(p.role::text, 'customer');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_user_role_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_user_role_counts()
  TO authenticated, service_role;

commit;

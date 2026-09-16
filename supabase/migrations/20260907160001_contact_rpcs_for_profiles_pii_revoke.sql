-- =============================================================================
-- profiles PII revoke'u için ilişki-doğrulayan iletişim RPC'leri
-- =============================================================================
-- AMAÇ
-- ----
-- `public.profiles` üzerindeki email / phone / last_known_lat / last_known_lng
-- sütunları `authenticated` rolünden kaldırılacak (bkz. 20260907110001 ve
-- 20260907110002'deki faz açıklaması). Bugün bu sütunları okuyan 24 meşru
-- çağrı noktası var; hepsinin ortak yanı, erişimin ROLE değil İLİŞKİYE
-- bağlı olması:
--
--   * admin        -> tüm kullanıcıların iletişimi
--   * satıcı       -> yalnız KENDİ dükkanının siparişindeki müşteri/kurye
--   * kurye        -> yalnız kendisine atanmış siparişler
--   * kullanıcı    -> yalnız kendi profili (public.get_my_profile zaten var)
--
-- RLS satır bazlıdır, sütun bazlı ayrım yapamaz; sütun GRANT'i ise rol
-- bazlıdır, ilişki bilemez. Bu yüzden ilişkiyi doğrulayan SECURITY DEFINER
-- RPC'ler tek doğru araçtır.
--
-- Bu migration YALNIZ yeni fonksiyon ekler; hiçbir mevcut yetkiyi
-- değiştirmez, dolayısıyla tek başına uygulanması güvenlidir.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Yardımcı: çağıran admin mi?
-- -----------------------------------------------------------------------------
-- Mevcut RLS politikalarındaki desenin aynısı; yeni bir yetki semantiği
-- icat etmiyoruz.
CREATE OR REPLACE FUNCTION private.caller_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
     WHERE p.id = (SELECT auth.uid())
       AND p.role = 'admin'::public.user_role
  );
$$;

REVOKE ALL ON FUNCTION private.caller_is_admin() FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 1) admin_profiles_contact — admin için iletişimli profil toplu getirme
-- -----------------------------------------------------------------------------
-- admin_profiles_minimal(uuid[]) zaten var ama email/phone döndürmüyor.
-- Admin panelindeki gömülü `profiles!inner(... email, phone)` sorgularının
-- yerini bu alacak.
CREATE OR REPLACE FUNCTION public.admin_profiles_contact(p_user_ids uuid[])
RETURNS TABLE (
  id         uuid,
  username   text,
  full_name  text,
  avatar_url text,
  email      text,
  phone      text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.caller_is_admin() THEN
    RAISE EXCEPTION 'admin_profiles_contact: yetki yok' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT p.id, p.username, p.full_name, p.avatar_url, p.email, p.phone
    FROM public.profiles p
   WHERE p.id = ANY(COALESCE(p_user_ids, ARRAY[]::uuid[]));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_profiles_contact(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_profiles_contact(uuid[])
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2) order_customer_contact — siparişin müşteri iletişimi
-- -----------------------------------------------------------------------------
-- Yetki: siparişin dükkan sahibi, siparişe atanmış kurye, siparişin sahibi
-- veya admin. Satıcı müşteriyi arayabilmeli, ama BAŞKA dükkanın müşterisine
-- erişememeli.
CREATE OR REPLACE FUNCTION public.order_customer_contact(p_order_ids uuid[])
RETURNS TABLE (
  order_id  uuid,
  user_id   uuid,
  full_name text,
  phone     text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT o.id, p.id, p.full_name, p.phone
    FROM public.orders o
    JOIN public.profiles p ON p.id = o.user_id
   WHERE o.id = ANY(COALESCE(p_order_ids, ARRAY[]::uuid[]))
     AND (
          private.caller_is_admin()
       OR o.user_id = (SELECT auth.uid())
       OR EXISTS (SELECT 1 FROM public.shops s
                   WHERE s.id = o.shop_id
                     AND s.owner_id = (SELECT auth.uid()))
       OR EXISTS (SELECT 1 FROM public.courier_assignments ca
                   WHERE ca.order_id = o.id
                     AND ca.courier_id = (SELECT auth.uid()))
     );
$$;

REVOKE ALL ON FUNCTION public.order_customer_contact(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.order_customer_contact(uuid[])
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3) order_courier_contacts — siparişe atanmış kuryenin iletişimi
-- -----------------------------------------------------------------------------
-- Yetki: siparişin dükkan sahibi, siparişin sahibi (müşteri kuryeyi
-- arayabilmeli), kuryenin kendisi veya admin.
CREATE OR REPLACE FUNCTION public.order_courier_contacts(p_order_ids uuid[])
RETURNS TABLE (
  order_id      uuid,
  assignment_id uuid,
  courier_id    uuid,
  full_name     text,
  phone         text,
  status        text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT o.id, ca.id, p.id, p.full_name, p.phone, ca.status::text
    FROM public.orders o
    JOIN public.courier_assignments ca ON ca.order_id = o.id
    JOIN public.profiles p ON p.id = ca.courier_id
   WHERE o.id = ANY(COALESCE(p_order_ids, ARRAY[]::uuid[]))
     AND (
          private.caller_is_admin()
       OR o.user_id = (SELECT auth.uid())
       OR ca.courier_id = (SELECT auth.uid())
       OR EXISTS (SELECT 1 FROM public.shops s
                   WHERE s.id = o.shop_id
                     AND s.owner_id = (SELECT auth.uid()))
     );
$$;

REVOKE ALL ON FUNCTION public.order_courier_contacts(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.order_courier_contacts(uuid[])
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4) admin_coupon_usage_contacts — kupon kullanım listesi
-- -----------------------------------------------------------------------------
-- `coupons` tablosunda shop_id/owner YOK; kuponlar global ve admin
-- yönetiminde. Bu yüzden erişim admin ile sınırlı.
CREATE OR REPLACE FUNCTION public.admin_coupon_usage_contacts(p_coupon_id uuid)
RETURNS TABLE (
  usage_id        uuid,
  user_id         uuid,
  full_name       text,
  email           text,
  discount_amount numeric,
  used_at         timestamptz,
  order_id        uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.caller_is_admin() THEN
    RAISE EXCEPTION 'admin_coupon_usage_contacts: yetki yok' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT cu.id, cu.user_id, p.full_name, p.email,
         cu.discount_amount, cu.used_at, cu.order_id
    FROM public.coupon_usages cu
    LEFT JOIN public.profiles p ON p.id = cu.user_id
   WHERE cu.coupon_id = p_coupon_id
   ORDER BY cu.used_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_coupon_usage_contacts(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_coupon_usage_contacts(uuid)
  TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- order_customer_contact: e-posta alanını ekle
-- =============================================================================
-- 20260907160001 bu RPC'yi full_name + phone ile tanımlamıştı. Ancak
-- lib/core/services/email_service.dart:32 ve :99 müşteri E-POSTASINI
-- okuyor ve bu çağrılar satıcı bağlamında yapılıyor:
--   order_service.dart:385  updateOrderStatus(delivered) -> müşteriye e-posta
-- Yani satıcı, kendi siparişinin müşterisine e-posta göndermek için
-- adresi okumak zorunda. İlişki doğrulaması aynı kalıyor, yalnız
-- döndürülen sütun kümesi genişliyor.
--
-- RETURNS TABLE değiştiği için önce DROP gerekiyor.
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.order_customer_contact(uuid[]);

CREATE FUNCTION public.order_customer_contact(p_order_ids uuid[])
RETURNS TABLE (
  order_id  uuid,
  user_id   uuid,
  full_name text,
  username  text,
  phone     text,
  email     text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT o.id, p.id, p.full_name, p.username, p.phone, p.email
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

COMMIT;

NOTIFY pgrst, 'reload schema';

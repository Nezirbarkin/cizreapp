-- ============================================================================
-- 20260809000001_fix_auth_is_admin_security_definer.sql
-- ----------------------------------------------------------------------------
-- BUG: Satıcı ürün eklerken "permission denied for schema auth" (42501).
--
-- KÖK NEDEN:
--   products INSERT'i, SECURITY DEFINER + sahibi "reward_points_owner" olan
--   trigger "enforce_product_points_eligibility_admin"ı tetikler. Bu trigger
--   public.auth_is_admin() çağırır. auth_is_admin() canlıda SECURITY INVOKER
--   olduğu için çağıran bağlamda — yani reward_points_owner olarak — çalışır.
--   reward_points_owner ise "auth" şemasında USAGE yetkisine sahip DEĞİLDİR
--   (teyit edildi). Bu yüzden auth.uid() erişimi "permission denied for
--   schema auth" (42501) ile çöker ve ürün kaydı (RPC + doğrudan INSERT
--   yollarının ikisi de aynı trigger'ı tetiklediği için) başarısız olur.
--
-- REGRESYON:
--   Migration 20260209000004 bu fonksiyonu SECURITY DEFINER (SET search_path =
--   public) olarak tanımlıyordu. Canlı DB'de INVOKER'a düşmüş (divergence).
--   Bu migration kanonik tanımı geri yükler.
--
-- ÇÖZÜM & GÜVENLİK:
--   Fonksiyonu CREATE OR REPLACE ile SECURITY DEFINER + postgres sahipliğinde
--   yeniden tanımlarız. Böylece hangi rolden çağrılırsa çağrılsın postgres
--   yetkisiyle "auth" şemasına ve (anon/authenticated'a revoke edilen)
--   "profiles.role" sütununa erişir. CREATE OR REPLACE kullanıyoruz çünkü
--   DROP ... CASCADE bağımlı policy/trigger'ları (sehirici, products vb.)
--   yok edebilirdi; REPLACE OID'yi ve tüm bağımlılıkları korur.
--   reward_points_owner'a "auth" şeması USAGE AÇILMAZ (least privilege).
-- ============================================================================

SET search_path = public, pg_temp;

-- Kanonik tanım: SECURITY DEFINER + STABLE + search_path = public.
-- Gövde değişmedi; yalnızca security context ve search_path deterministik
-- hale getirildi.
CREATE OR REPLACE FUNCTION public.auth_is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'admin'
  );
$$;

-- EXECUTE grant'ları (idempotent).
-- reward_points_owner = products trigger'ının efektif rolü; auth_is_admin()'ı
-- çağırabilmesi şart (EXECUTE zaten vardı, burada garanti altına alınıyor).
GRANT EXECUTE ON FUNCTION public.auth_is_admin()
  TO authenticated, service_role, reward_points_owner;

COMMENT ON FUNCTION public.auth_is_admin() IS
  'Çağıran kullanıcının admin olup olmadığını döner. SECURITY DEFINER (postgres sahipliği): "auth" şemasına ve profiles.role sütununa erişebilmek için. reward_points_owner gibi auth USAGE yetkisi olmayan rollerin bağlamında (ör. products "enforce_product_points_eligibility_admin" triggerı) güvenle çağrılabilir. (2026-08-09 regresyon düzeltmesi: INVOKER -> DEFINER)';

-- PostgREST şema cache'ini tazele. Fonksiyon imzası değişmediği için zorunlu
-- değil, ancak güvenlik tarafı değiştiğinden tutarlılık için tetikliyoruz.
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
  RAISE NOTICE '✓ PostgREST schema cache reload tetiklendi';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pgrst reload başarısız: %. Dashboard > API > Reload schema cache kullanın.', SQLERRM;
END;
$$;

-- ============================================================================
-- DOĞRULAMA (migration sonrası SQL Editor'da çalıştır):
--   SELECT proname, prosecdef AS security_definer, proconfig
--   FROM pg_proc WHERE proname = 'auth_is_admin';
--   Beklenen: prosecdef = true , proconfig = {search_path=public}
-- ============================================================================

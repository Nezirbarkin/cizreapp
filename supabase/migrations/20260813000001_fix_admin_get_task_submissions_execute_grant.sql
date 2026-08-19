-- =============================================================================
-- 20260813000001_fix_admin_get_task_submissions_execute_grant.sql
--
-- admin_get_task_submissions RPC hatası:
--   42501 permission denied for function admin_get_task_submissions
--
-- Sebep: Repo'daki tanımlayıcı migration'lar (20260719000002 ve 20260720000003)
-- fonksiyonu SECURITY DEFINER olarak tanımlayıp EXECUTE yetkisini
-- authenticated + service_role'a veriyor. Canlı veritabanında fonksiyon VAR
-- (42501 = "yetkisiz"; yoksa 404/PGRST202 "bulunamadı" hatası alınırdı) ama
-- authenticated rolünün EXECUTE yetkisi eksik. Bu, canlı DB'de fonksiyonun
-- DROP+CREATE ile yeniden oluşturulması (CREATE OR REPLACE ACL'leri korur ama
-- DROP eder), eksik/tam uygulanmamış migration veya manuel bir REVOKE sonucu
-- oluşan "grant drift"tir. Repo tarafında migration'lar doğru; bu migration
-- yalnızca canlı DB'deki kaymış yetkiyi onarır.
--
-- Çözüm: EXECUTE yetkisini yeniden verip PostgREST şema önbelleğini yenile.
-- Idempotent'tir — her koşulda authenticated + service_role'a EXECUTE verir.
--
-- Doğrulama (SQL Editor, migration sonrası):
--   SELECT has_function_privilege('authenticated',
--          'admin_get_task_submissions(task_submission_status, uuid, integer, integer)',
--          'execute');  -- true dönmeli
-- =============================================================================

SET search_path = public, pg_temp;

-- 1) PUBLIC'ten yürütme yetkisini kaldır (anon erişimi olmasın)
REVOKE ALL ON FUNCTION public.admin_get_task_submissions(task_submission_status, UUID, INTEGER, INTEGER) FROM PUBLIC;

-- 2) authenticated + service_role'a EXECUTE ver (Dart çağırıcının bağımlı olduğu yetki)
GRANT EXECUTE ON FUNCTION public.admin_get_task_submissions(task_submission_status, UUID, INTEGER, INTEGER) TO authenticated, service_role;

-- 3) PostgREST şema önbelleğini yenile (yeni yetki hemen devreye girsin)
NOTIFY pgrst, 'reload schema';

-- 4) Doğrulama bildirimi
DO $$
DECLARE
  v_ok BOOLEAN;
BEGIN
  SELECT has_function_privilege(
    'authenticated',
    'admin_get_task_submissions(task_submission_status, uuid, integer, integer)',
    'execute'
  ) INTO v_ok;

  IF v_ok THEN
    RAISE NOTICE '✅ 20260813000001 — authenticated EXECUTE yetkisi doğrulandı';
  ELSE
    RAISE NOTICE '⚠️ 20260813000001 — authenticated hâlâ EXECUTE edemiyor! Fonksiyon imzasını/sahibini kontrol edin';
  END IF;
END $$;

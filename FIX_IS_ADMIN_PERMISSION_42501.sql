-- =============================================================================
-- FIX_IS_ADMIN_PERMISSION_42501.sql
-- "permission denied for function is_admin" (42501) kesin çözüm.
--
-- KÖK NEDEN:
--   is_admin() fonksiyonuna authenticated rolü için EXECUTE yetkisi
--   hiç verilmemiş. profiles_update_own policy'si is_admin() çağırıyor.
--   Admin rol değiştirme → profiles UPDATE → RLS → is_admin() → 42501.
--
--   NOT: auth_is_admin() fonksiyonunun yetkileri TAMDIR (authenticated=EXECUTE).
--   Ama profiles_update_own policy'si is_admin() kullanıyor, auth_is_admin() değil.
--
-- ÇÖZÜM:
--   1. is_admin() fonksiyonuna authenticated EXECUTE yetkisi ver
--   2. anon rolünden EXECUTE yetkisini iptal et (güvenlik)
--   3. Mevcut fonksiyon tanımını doğrula (SECURITY DEFINER + SET search_path)
--
-- YAN ETKİ ANALİZİ:
--   - is_admin() SECURITY DEFINER → postgres yetkisiyle çalışır, RLS bypass eder.
--     Bu DOĞRU davranış: admin kontrolü RLS'den etkilenmemeli.
--   - authenticated rolü artık is_admin() çağırabilir → FALSE döner (admin değilse)
--     veya TRUE döner (admin ise). Bu zaten istenen davranış.
--   - profiles_update_own policy: id=auth.uid() OR is_admin() → artık çalışacak.
--   - Diğer tablolardaki is_admin() kullanan policy'ler de düzelecek (ai_settings, vb).
--
-- ROLLBACK:
--   REVOKE EXECUTE ON FUNCTION public.is_admin() FROM authenticated;
--   (Bu dosyayı çalıştırmadan ÖNCEKI duruma döner)
-- =============================================================================

-- [1] MEVCUT DURUMU KONTROL ET
SELECT
  n.nspname AS schema,
  p.proname AS function_name,
  COALESCE(p.proacl::text, 'NULL proacl') AS acl_before,
  p.prosecdef AS is_security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'is_admin';

-- [2] GRANT EXECUTE — ASIL DÜZELTME
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- [3] REVOKE FROM ANON — GÜVENLİK (anon erişimi olmamalı)
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM anon;

-- [4] FONKSİYON TANIMINI DOĞRULA (SECURITY DEFINER + search_path korundu mu?)
-- NOT: CREATE OR REPLACE yapmıyoruz, sadece GRANT ekliyoruz.
-- Fonksiyon gövdesi migration'lardan gelen haliyle korunuyor.
SELECT
  proname,
  prosecdef AS is_security_definer,
  pg_get_functiondef(oid) AS full_definition
FROM pg_proc
WHERE proname = 'is_admin'
  AND pronamespace = 'public'::regnamespace;

-- [5] YETKİLERİ DOĞRULA (GRANT sonrası)
SELECT
  routine_schema,
  routine_name,
  grantee,
  privilege_type,
  is_grantable
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name = 'is_admin'
ORDER BY grantee, privilege_type;

-- [6] profiles_update_own POLICY DOĞRULAMA
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'profiles'
  AND cmd = 'UPDATE';

-- [7] HIZLI TEST (opsiyonel — admin kullanıcıyla oturum açınca)
-- Aşağıdaki sorguyu authenticated kullanıcıyla çalıştırın:
-- SELECT public.is_admin();
-- Beklenen: admin ise TRUE, değilse FALSE. 42501 OLMAMALI.

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'FIX_IS_ADMIN_PERMISSION_42501 TAMAMLANDI';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'is_admin() fonksiyonuna authenticated EXECUTE yetkisi verildi';
    RAISE NOTICE 'is_admin() fonksiyonundan anon EXECUTE yetkisi iptal edildi';
    RAISE NOTICE 'Fonksiyon tanımı (SECURITY DEFINER + search_path) korundu';
    RAISE NOTICE '';
    RAISE NOTICE 'TEST: Admin panelde rol değiştirme işlemini deneyin.';
    RAISE NOTICE 'Beklenen: 42501 hatası GİTMEZSE, DIAG sorgularını tekrar çalıştırın.';
    RAISE NOTICE '========================================';
END $$;
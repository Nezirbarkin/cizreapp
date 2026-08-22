-- ============================================================================
-- 20260709000007_TRANSFER_RPC_REVOKE_PUBLIC.sql
-- ============================================================================
-- Amaç: Havale onay RPC'leri (approve_transfer_confirmation /
--       reject_transfer_confirmation) için Supabase linter WARN'ını gidermek:
--       "Public Can Execute SECURITY DEFINER Function" (0028 / 0029).
--
-- Durum: Bu fonksiyonlar SECURITY DEFINER'dır (kasıtlı — add_to_balance
--        çağırırken RLS bypass gerekiyor) ve içeride açık admin rol kontrolü
--        vardır (auth.uid() + profiles.role='admin'). Yani authenticated
--        rolüne açık olmaları güvenlik açığı değildir; normal kullanıcı
--        çağırırsa RPC "Bu işlem sadece admin tarafından yapılabilir"
--        hatası fırlatır (ERRCODE 42501).
--
-- Sorun: Postgres'te GRANT EXECUTE TO authenticated verildiğinde, PUBLIC
--        üzerinden tanımlı varsayılan EXECUTE yetkisi hâlâ anon rolünün
--        fonksiyonu çağırabilmesine izin verebilir (INHERIT). Linter bunu
--        "anon executable" olarak işaretler.
--
-- Çözüm: Varsayılan PUBLIC EXECUTE yetkisini açıkça REVOKE et; yalnızca
--        authenticated için GRANT'ı yeniden ver. Böylece anon doğrudan veya
--        dolaylı olarak bu RPC'leri çağıramaz; giriş yapmış kullanıcılar
--        çağırabilir (içeride admin kontrolü zaten var).
--
-- Idempotent: REVOKE güvenlidir, tekrar tekrar çalıştırılabilir.
-- ============================================================================

BEGIN;

-- approve_transfer_confirmation
REVOKE EXECUTE ON FUNCTION public.approve_transfer_confirmation(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_transfer_confirmation(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.approve_transfer_confirmation(UUID, TEXT) TO authenticated;

-- reject_transfer_confirmation
REVOKE EXECUTE ON FUNCTION public.reject_transfer_confirmation(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reject_transfer_confirmation(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_transfer_confirmation(UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================================
-- DOĞRULAMA
-- ============================================================================
-- SELECT proname, (aclexplode(proacl)).grantee::regrole AS grantee,
--        (aclexplode(proacl)).privilege_type AS priv
-- FROM pg_proc
-- WHERE proname IN ('approve_transfer_confirmation','reject_transfer_confirmation');
-- Beklenen: sadece authenticated = X (EXECUTE), anon/PUBLIC görünmemeli.
-- ============================================================================
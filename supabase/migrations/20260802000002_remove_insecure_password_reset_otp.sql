-- =============================================================================
-- GÜVENSİZ ÖZEL ŞİFRE SIFIRLAMA OTP SİSTEMİNİ KALDIR
-- ----------------------------------------------------------------------------
-- Tespit edilen açıklar (2026-08-02):
--   1) public.password_reset_otps tablosu OTP kodlarını AÇIK METİN saklıyordu.
--   2) public.verify_password_reset_otp(text,text) SECURITY DEFINER + anon
--      erişimi ile 6 haneli kodu RPC üzerinden brute-force edilebiliyordu.
--      Brute-force koruması (failed_attempt sayacı, IP rate limit) yoktu.
--   3) Supabase functions/reset-password-with-otp index.ts service-role
--      anahtarı ile kullanıcının şifresini değiştiriyordu; tek kullanımlık
--      recovery token veya session doğrulaması yapmıyor, used=true kaydını
--      10 dakika boyunca yeniden oynatabiliyordu.
--   4) Edge Function'larda Math.random() ile OTP üretimi.
--
-- Düzeltme:
--   Supabase Auth'un yerleşik recovery OTP sistemi (verifyOTP / OtpType.recovery)
--   kullanılıyor. Bu özel tablo + RPC + Edge Function ihtiyaç dışı kaldı.
--
-- Bu migration:
--   - verify_password_reset_otp fonksiyonunun TÜM overload'larında EXECUTE
--     yetkisini PUBLIC, anon, authenticated'dan kaldırır.
--   - Fonksiyonu DROP FUNCTION IF EXISTS ile güvenle kaldırır.
--   - password_reset_otps tablosunu bağlı policy + index + RLS dahil kaldırır.
--   - Idempotent ve ileri yönlüdür.
--   - registration_otps ve verify_registration_otp'a DOKUNMAZ.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) verify_password_reset_otp: PUBLIC/anon/authenticated'dan EXECUTE kaldır
--    (idempotent — daha önceki migration zaten GRANT yaptıysa bile güvenli)
-- -----------------------------------------------------------------------------
DO $revoke_reset_otp$
DECLARE
  v_function regprocedure;
BEGIN
  FOR v_function IN
    SELECT p.oid::regprocedure
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'verify_password_reset_otp'
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      v_function
    );
  END LOOP;
END
$revoke_reset_otp$;

-- -----------------------------------------------------------------------------
-- 2) Fonksiyonu kaldır (var olsun/olmasın idempotent)
--    regprocedure üzerinden tüm overload'ları güvenle siler.
-- -----------------------------------------------------------------------------
DO $drop_reset_otp_func$
DECLARE
  v_function regprocedure;
BEGIN
  FOR v_function IN
    SELECT p.oid::regprocedure
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'verify_password_reset_otp'
  LOOP
    EXECUTE format('DROP FUNCTION %s', v_function);
  END LOOP;
END
$drop_reset_otp_func$;

-- -----------------------------------------------------------------------------
-- 3) password_reset_otps tablosunu güvenle kaldır
--    - Policy varsa kaldır (RLS açık olabilir)
--    - Indexler CASCADE ile gider
--    - Tabloyu CASCADE ile kaldır
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Service role full access on password_reset_otps"
  ON password_reset_otps;

DROP INDEX IF EXISTS idx_password_reset_otps_email;

DROP TABLE IF EXISTS password_reset_otps CASCADE;

-- -----------------------------------------------------------------------------
-- 4) Yorum: registration_otps ve verify_registration_otp bu migration'ın
--    kapsamı dışındadır ve bilinçli olarak korunur.
-- -----------------------------------------------------------------------------

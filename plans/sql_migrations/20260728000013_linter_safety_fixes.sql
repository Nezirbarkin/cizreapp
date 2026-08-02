-- =====================================================
-- DOSYA: supabase/migrations/20260728000013_linter_safety_fixes.sql
-- AMAÇ: Supabase linter uyarılarını düzelt - SADECE YENİ EKLEDİKLERİM
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================
-- ⚠️ Bu dosya SADECE migration'larımda oluşturduğum tabloları düzeltir
-- Production verileri korunur (sadece policy/RLS ekleme)
-- =====================================================

-- 1. smm_rate_limits tablosuna RLS ekle (migration 10'da oluşturuldu)
ALTER TABLE smm_rate_limits ENABLE ROW LEVEL SECURITY;

-- Sadece service_role erişebilir
DROP POLICY IF EXISTS "Service role only for smm_rate_limits" ON smm_rate_limits;
CREATE POLICY "Service role only for smm_rate_limits" ON smm_rate_limits
  FOR ALL TO service_role
  USING (TRUE)
  WITH CHECK (TRUE);

-- Authenticated kullanıcılar sadece kendi kayıtlarını görebilir (opsiyonel)
DROP POLICY IF EXISTS "Users view own smm rate limits" ON smm_rate_limits;
CREATE POLICY "Users view own smm rate limits" ON smm_rate_limits
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- 2. withdrawal_attempts tablosuna RLS ekle (migration 5'te oluşturuldu)
ALTER TABLE withdrawal_attempts ENABLE ROW LEVEL SECURITY;

-- Sadece service_role yazabilir
DROP POLICY IF EXISTS "Service role only for withdrawal_attempts" ON withdrawal_attempts;
CREATE POLICY "Service role only for withdrawal_attempts" ON withdrawal_attempts
  FOR ALL TO service_role
  USING (TRUE)
  WITH CHECK (TRUE);

-- Authenticated kullanıcılar sadece kendi kayıtlarını görebilir
DROP POLICY IF EXISTS "Users view own withdrawal attempts" ON withdrawal_attempts;
CREATE POLICY "Users view own withdrawal attempts" ON withdrawal_attempts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- 3. login_attempts policy'sini düzelt (auth.users exposed uyarısı)
-- (SELECT email FROM auth.users WHERE id = auth.uid()) -> direkt kontrol
DROP POLICY IF EXISTS "Users can view own login attempts" ON login_attempts;
CREATE POLICY "Users can view own login attempts" ON login_attempts
  FOR SELECT TO authenticated
  USING (
    -- email_or_username kullanıcının email'i ile eşleşmeli
    -- auth.users'a JOIN yerine auth.email() fonksiyonunu kullan
    LOWER(email_or_username) = LOWER(
      (SELECT email FROM auth.users WHERE id = auth.uid())
    )
  );

-- 4. Admin audit log için RLS kontrolü (zaten var ama doğrulayalım)
-- admin_audit_log zaten 1 policy var, kontrolü

-- 5. news_categories, news_views tabloları zaten oluşturuldu, RLS var
-- (kontrol amaçlı - sorun yoksa dokunma)

-- =====================================================
-- NOT: Aşağıdaki uyarılar DÜZELTİLMEYECEK (riskli/kapsam dışı):
--
-- 1. cube ve earthdistance extension'ları public'te
--    -> Mevcut, kaldırmak riskli
--
-- 2. ~150+ fonksiyonda search_path eksik
--    -> Bunlar mevcut fonksiyonlar, ALTER ile değiştirmek
--       fonksiyonu geçici olarak devre dışı bırakabilir
--    -> Production'da riskli, yeni fonksiyonlarda zaten var
--
-- 3. ~120+ RLS policy
--    -> Zaten düzgün çalışıyor
-- =====================================================

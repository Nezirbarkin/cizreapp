-- ============================================================================
-- SUPABASE LINTER HATALARINI DÜZELT
-- Auth RLS InitPlan ve Multiple Permissive Policies sorunlarını çöz
-- ============================================================================

-- 1. AUTH RLS INITPLAN SORUNUNU DÜZELT
-- auth.uid() yerine (select auth.uid()) kullan - Her satır için tekrar değerlendirilmesini engeller
-- ============================================================================

-- user_reports tablosu
DROP POLICY IF EXISTS "Kullanıcılar kendi şikayetlerini görebilir" ON user_reports;
CREATE POLICY "Kullanıcılar kendi şikayetlerini görebilir"
  ON user_reports FOR SELECT
  TO authenticated
  USING ((select auth.uid()) = reporter_id AND reporter_id IS NOT NULL);

DROP POLICY IF EXISTS "Kullanıcılar şikayet oluşturabilir" ON user_reports;
CREATE POLICY "Kullanıcılar şikayet oluşturabilir"
  ON user_reports FOR INSERT
  TO authenticated
  WITH CHECK (
    (select auth.uid()) = reporter_id 
    AND reporter_id != reported_user_id
    AND reporter_id IS NOT NULL
    AND reported_user_id IS NOT NULL
  );

-- blocked_users tablosu
DROP POLICY IF EXISTS "Kullanıcılar kendi engelleme listesini görebilir" ON blocked_users;
CREATE POLICY "Kullanıcılar kendi engelleme listesini görebilir"
  ON blocked_users FOR SELECT
  TO authenticated
  USING ((select auth.uid()) = blocker_id AND blocker_id IS NOT NULL);

DROP POLICY IF EXISTS "Kullanıcılar engelleyebilir" ON blocked_users;
CREATE POLICY "Kullanıcılar engelleyebilir"
  ON blocked_users FOR INSERT
  TO authenticated
  WITH CHECK (
    (select auth.uid()) = blocker_id 
    AND blocker_id != blocked_id
    AND blocker_id IS NOT NULL
    AND blocked_id IS NOT NULL
  );

DROP POLICY IF EXISTS "Kullanıcılar engelini kaldırabilir" ON blocked_users;
CREATE POLICY "Kullanıcılar engelini kaldırabilir"
  ON blocked_users FOR DELETE
  TO authenticated
  USING ((select auth.uid()) = blocker_id AND blocker_id IS NOT NULL);

-- support_tickets tablosu - Eski duplicate politikaları sil
DROP POLICY IF EXISTS "Kullanıcılar kendi taleplerini görebilir" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_select_policy" ON support_tickets;
DROP POLICY IF EXISTS "Kullanıcılar talep oluşturabilir" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_insert_policy" ON support_tickets;
DROP POLICY IF EXISTS "Admin taleplerini güncelleyebilir" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_update_policy" ON support_tickets;

-- Yeni tek politikalar oluştur
CREATE POLICY "Kullanıcılar kendi taleplerini görebilir veya admin"
  ON support_tickets FOR SELECT
  TO authenticated
  USING (
    (select auth.uid()) = user_id 
    OR (select auth.uid()) IN (SELECT id FROM profiles WHERE role = 'admin')
  );

CREATE POLICY "Kullanıcılar talep oluşturabilir"
  ON support_tickets FOR INSERT
  TO authenticated
  WITH CHECK ((select auth.uid()) = user_id AND user_id IS NOT NULL);

CREATE POLICY "Admin veya kullanıcı güncelleyebilir"
  ON support_tickets FOR UPDATE
  TO authenticated
  USING (
    (select auth.uid()) IN (SELECT id FROM profiles WHERE role = 'admin')
    OR (select auth.uid()) = user_id
  )
  WITH CHECK (
    (select auth.uid()) IN (SELECT id FROM profiles WHERE role = 'admin')
    OR (select auth.uid()) = user_id
  );

-- audit_log tablosu
DROP POLICY IF EXISTS "Admin audit log'u görebilir" ON audit_log;
CREATE POLICY "Admin audit log'u görebilir"
  ON audit_log FOR SELECT
  TO authenticated
  USING (
    (select auth.uid()) IN (SELECT id FROM profiles WHERE role = 'admin')
  );

-- 2. SHOP_REVIEWS MULTIPLE PERMISSIVE POLICIES SORUNUNU DÜZELT
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view reviews" ON shop_reviews;
DROP POLICY IF EXISTS "Users can view own reviews" ON shop_reviews;

-- Tek birleştirilmiş politika
CREATE POLICY "Herkes yorumları görebilir"
  ON shop_reviews FOR SELECT
  TO authenticated
  USING (true);

-- 3. FAQS İÇİN DE AUTH.UID() DÜZELTMESİ (eğer varsa)
-- ============================================================================

DROP POLICY IF EXISTS "Herkes aktif SSS'leri görebilir" ON faqs;
CREATE POLICY "Herkes aktif SSS'leri görebilir"
  ON faqs FOR SELECT
  TO authenticated
  USING (is_active = true);

-- 4. RATE LIMIT TABLOSU İÇİN RLS
-- ============================================================================

ALTER TABLE report_rate_limit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin rate limit görebilir" ON report_rate_limit;
CREATE POLICY "Admin rate limit görebilir"
  ON report_rate_limit FOR SELECT
  TO authenticated
  USING (
    (select auth.uid()) IN (SELECT id FROM profiles WHERE role = 'admin')
  );

-- ============================================================================
-- SONUÇ VE DOĞRULAMA
-- ============================================================================

-- Tüm politikaları listele (doğrulama için)
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('user_reports', 'blocked_users', 'support_tickets', 'audit_log', 'shop_reviews', 'report_rate_limit', 'faqs')
ORDER BY tablename, policyname;

SELECT '✅ Tüm linter hataları düzeltildi!' as result;

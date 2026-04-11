-- =====================================================
-- USER_REPORTS - TAM RLS DÜZELTME
-- Hem INSERT (kullanıcılar şikayet oluşturabilsin)
-- hem SELECT (admin görebilsin) politikaları
-- =====================================================

-- 1) RLS aktif mi kontrol et
ALTER TABLE user_reports ENABLE ROW LEVEL SECURITY;

-- 2) Mevcut tüm politikaları temizle
DROP POLICY IF EXISTS "Kullanıcılar şikayet oluşturabilir" ON user_reports;
DROP POLICY IF EXISTS "user_reports_insert_policy" ON user_reports;
DROP POLICY IF EXISTS "user_reports_select_policy" ON user_reports;
DROP POLICY IF EXISTS "user_reports_select_unified" ON user_reports;
DROP POLICY IF EXISTS "user_reports_select" ON user_reports;
DROP POLICY IF EXISTS "user_reports_update_policy" ON user_reports;
DROP POLICY IF EXISTS "user_reports_delete_policy" ON user_reports;
DROP POLICY IF EXISTS "Adminler tüm raporları görebilir" ON user_reports;

-- 3) INSERT politikası - Giriş yapmış kullanıcılar kendi adına şikayet oluşturabilir
CREATE POLICY "user_reports_insert"
  ON user_reports
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = reporter_id);

-- 4) SELECT politikası - Kullanıcı kendi şikayetlerini, admin hepsini görebilir
CREATE POLICY "user_reports_select"
  ON user_reports
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = reporter_id
    OR
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- 5) UPDATE politikası - Sadece admin güncelleyebilir
CREATE POLICY "user_reports_update"
  ON user_reports
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- 6) DELETE politikası - Sadece admin silebilir
CREATE POLICY "user_reports_delete"
  ON user_reports
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.is_admin = true
    )
  );

-- 7) Kontrol - Politikaları listele
SELECT 
  policyname,
  permissive,
  roles,
  cmd
FROM pg_policies
WHERE tablename = 'user_reports'
ORDER BY cmd;

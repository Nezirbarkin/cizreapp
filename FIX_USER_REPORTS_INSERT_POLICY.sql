-- =====================================================
-- USER_REPORTS INSERT POLICY FIX
-- Kullanıcı şikayet sistemi için INSERT politikası
-- =====================================================

-- user_reports tablosuna authenticated kullanıcıların insert yapabilmesi için politika

-- Önce eski politikayı kaldır (varsa)
DROP POLICY IF EXISTS "Kullanıcılar şikayet oluşturabilir" ON user_reports;
DROP POLICY IF EXISTS "user_reports_insert_policy" ON user_reports;

-- Yeni INSERT politikası oluştur
CREATE POLICY "user_reports_insert_policy"
  ON user_reports
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = reporter_id
  );

-- Politikayı etkinleştir
ALTER TABLE user_reports ENABLE ROW LEVEL SECURITY;

-- Kontrol
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'user_reports';


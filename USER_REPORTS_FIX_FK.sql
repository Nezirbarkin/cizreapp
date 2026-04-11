-- ============================================================================
-- user_reports Tablosu Foreign Key Düzeltmesi
-- ============================================================================
-- Sorun: user_reports tablosu auth.users'a referans veriyor ama
-- Supabase sorguları profiles tablosuna join yapmaya çalışıyor.
-- Çözüm: Foreign key'leri profiles tablosuna çevireceğiz.
-- ============================================================================

-- Önce mevcut tabloyu yedekleyelim (varsa)
CREATE TABLE IF NOT EXISTS user_reports_backup AS 
SELECT * FROM user_reports;

-- Mevcut tabloyu drop edelim (veriler varsa yedekte durur)
DROP TABLE IF EXISTS user_reports CASCADE;

-- Yeni tabloyu doğru foreign key'lerle oluştur
CREATE TABLE user_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reported_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  description TEXT,
  images TEXT[],  -- Şikayete eklenen görsel URL'leri (max 3)
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'reviewing', 'resolved', 'rejected')),
  admin_response TEXT,  -- Admin cevabı
  admin_id UUID REFERENCES profiles(id),  -- Hangi admin işlem yaptı
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Kendini şikayet edemez
  CHECK (reporter_id != reported_user_id)
);

-- Yedeği geri yükle (varsa)
INSERT INTO user_reports (id, reporter_id, reported_user_id, reason, description, status, created_at, updated_at)
SELECT id, reporter_id, reported_user_id, reason, description, status, created_at, updated_at
FROM user_reports_backup
ON CONFLICT DO NOTHING;

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter ON user_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported ON user_reports(reported_user_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_status ON user_reports(status);
CREATE INDEX IF NOT EXISTS idx_user_reports_created_at ON user_reports(created_at DESC);

-- RLS'yi tekrar aktif et
ALTER TABLE user_reports ENABLE ROW LEVEL SECURITY;

-- Politikaları temizle ve yeniden oluştur
DROP POLICY IF EXISTS "Kullanıcılar kendi şikayetlerini görebilir" ON user_reports;
DROP POLICY IF EXISTS "Kullanıcılar şikayet oluşturabilir" ON user_reports;
DROP POLICY IF EXISTS "Admin tüm şikayetleri görebilir" ON user_reports;
DROP POLICY IF EXISTS "Admin şikayetleri güncelleyebilir" ON user_reports;
DROP POLICY IF EXISTS "Admin şikayetleri silebilir" ON user_reports;

-- Kullanıcı politikaları
CREATE POLICY "Kullanıcılar kendi şikayetlerini görebilir"
  ON user_reports FOR SELECT
  TO authenticated
  USING (auth.uid() = reporter_id);

CREATE POLICY "Kullanıcılar şikayet oluşturabilir"
  ON user_reports FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = reporter_id 
    AND reporter_id != reported_user_id  -- Kendini şikayet edemez
  );

-- Admin politikaları
CREATE POLICY "Admin tüm şikayetleri görebilir"
  ON user_reports FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  );

CREATE POLICY "Admin şikayetleri güncelleyebilir"
  ON user_reports FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  );

CREATE POLICY "Admin şikayetleri silebilir"
  ON user_reports FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  );

-- Updated_at trigger
DROP TRIGGER IF EXISTS user_reports_updated_at ON user_reports;
CREATE TRIGGER user_reports_updated_at
  BEFORE UPDATE ON user_reports
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- Yedek tabloyu drop et
DROP TABLE IF EXISTS user_reports_backup;

-- Sonuçları göster
SELECT 'user_reports tablosu başarıyla güncellendi!' as status;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'user_reports' 
ORDER BY ordinal_position;

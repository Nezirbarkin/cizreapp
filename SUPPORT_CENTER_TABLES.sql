-- Destek Merkezi için gerekli tablolar

-- 1. Kullanıcı Şikayetleri Tablosu
CREATE TABLE IF NOT EXISTS user_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reported_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'reviewing', 'resolved', 'rejected')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Aynı kullanıcı aynı kişiyi birden fazla şikayet etmesin
  UNIQUE(reporter_id, reported_user_id)
);

-- 2. Engellenmiş Kullanıcılar Tablosu
CREATE TABLE IF NOT EXISTS blocked_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Aynı kullanıcı aynı kişiyi birden fazla engelleyemesin
  UNIQUE(blocker_id, blocked_id),
  
  -- Kendini engelleyemesin
  CHECK (blocker_id != blocked_id)
);

-- 3. Destek Talepleri Tablosu
CREATE TABLE IF NOT EXISTS support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('general', 'account', 'payment', 'order', 'technical', 'other')),
  message TEXT NOT NULL,
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
  admin_response TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. SSS (Sıkça Sorulan Sorular) Tablosu
CREATE TABLE IF NOT EXISTS faqs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  category TEXT DEFAULT 'general',
  "order" INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter ON user_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported ON user_reports(reported_user_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_status ON user_reports(status);

CREATE INDEX IF NOT EXISTS idx_blocked_users_blocker ON blocked_users(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked ON blocked_users(blocked_id);

CREATE INDEX IF NOT EXISTS idx_support_tickets_user ON support_tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_created ON support_tickets(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_faqs_active ON faqs(is_active);
CREATE INDEX IF NOT EXISTS idx_faqs_order ON faqs("order");

-- RLS Politikaları

-- user_reports için RLS
ALTER TABLE user_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Kullanıcılar kendi şikayetlerini görebilir"
  ON user_reports FOR SELECT
  TO authenticated
  USING (auth.uid() = reporter_id);

CREATE POLICY "Kullanıcılar şikayet oluşturabilir"
  ON user_reports FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = reporter_id);

-- blocked_users için RLS
ALTER TABLE blocked_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Kullanıcılar kendi engelleme listesini görebilir"
  ON blocked_users FOR SELECT
  TO authenticated
  USING (auth.uid() = blocker_id);

CREATE POLICY "Kullanıcılar engelleyebilir"
  ON blocked_users FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = blocker_id);

CREATE POLICY "Kullanıcılar engelini kaldırabilir"
  ON blocked_users FOR DELETE
  TO authenticated
  USING (auth.uid() = blocker_id);

-- support_tickets için RLS
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Kullanıcılar kendi taleplerini görebilir"
  ON support_tickets FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Kullanıcılar talep oluşturabilir"
  ON support_tickets FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- faqs için RLS (herkes aktif SSS'leri görebilir)
ALTER TABLE faqs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Herkes aktif SSS'leri görebilir"
  ON faqs FOR SELECT
  TO authenticated
  USING (is_active = true);

-- Örnek SSS verileri ekle
INSERT INTO faqs (question, answer, category, "order") VALUES
('Siparişimi nasıl takip edebilirim?', 'Siparişlerinizi "Siparişlerim" sayfasından takip edebilirsiniz. Her siparişin detaylarını görmek için sipariş numarasına tıklayın.', 'order', 1),
('Ödeme yöntemleri nelerdir?', 'Kredi kartı, banka kartı ve kapıda ödeme seçeneklerini kullanabilirsiniz. Tüm ödemeler güvenli SSL sertifikası ile korunmaktadır.', 'payment', 2),
('Teslimat süresi ne kadardır?', 'Normal teslimat 2-3 iş günü içinde gerçekleşir. Hızlı teslimat seçeneği ile aynı gün teslimat imkanı da mevcuttur.', 'order', 3),
('Hesabımı nasıl silebilirim?', 'Hesap silme işlemi için Ayarlar > Hesap > Hesabı Sil seçeneklerini takip edebilirsiniz. Hesap silme işlemi geri alınamaz.', 'account', 4),
('Şifremi unuttum, ne yapmalıyım?', 'Giriş ekranında "Şifremi Unuttum" seçeneğine tıklayarak e-posta adresinize şifre sıfırlama bağlantısı gönderebilirsiniz.', 'account', 5),
('Ürün iadesi nasıl yapılır?', 'Ürün tesliminden sonraki 14 gün içinde iade talebinde bulunabilirsiniz. Siparişlerim > Sipariş Detay > İade Et butonunu kullanın.', 'order', 6)
ON CONFLICT DO NOTHING;

-- updated_at trigger'ları
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER user_reports_updated_at
  BEFORE UPDATE ON user_reports
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER support_tickets_updated_at
  BEFORE UPDATE ON support_tickets
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER faqs_updated_at
  BEFORE UPDATE ON faqs
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

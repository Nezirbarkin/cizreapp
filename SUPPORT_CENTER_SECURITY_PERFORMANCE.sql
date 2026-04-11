-- ============================================================================
-- SUPPORT CENTER - GÜVENLIK VE PERFORMANS İYİLEŞTİRMELERİ
-- ============================================================================

-- 1. GÜVENLIK - RLS POLİTİKALARI İYİLEŞTİRME
-- ============================================================================

-- user_reports tablosu - Şikayetleri görme kuralı (sadece kendi şikayetlerini görebilir)
DROP POLICY IF EXISTS "Kullanıcılar kendi şikayetlerini görebilir" ON user_reports;
CREATE POLICY "Kullanıcılar kendi şikayetlerini görebilir"
  ON user_reports FOR SELECT
  TO authenticated
  USING (auth.uid() = reporter_id AND reporter_id IS NOT NULL);

-- Şikayet oluşturma - Kendini şikayet edemez
DROP POLICY IF EXISTS "Kullanıcılar şikayet oluşturabilir" ON user_reports;
CREATE POLICY "Kullanıcılar şikayet oluşturabilir"
  ON user_reports FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = reporter_id 
    AND reporter_id != reported_user_id
    AND reporter_id IS NOT NULL
    AND reported_user_id IS NOT NULL
  );

-- blocked_users tablosu - Engelleme kurallarını iyileştir
DROP POLICY IF EXISTS "Kullanıcılar kendi engelleme listesini görebilir" ON blocked_users;
CREATE POLICY "Kullanıcılar kendi engelleme listesini görebilir"
  ON blocked_users FOR SELECT
  TO authenticated
  USING (auth.uid() = blocker_id AND blocker_id IS NOT NULL);

DROP POLICY IF EXISTS "Kullanıcılar engelleyebilir" ON blocked_users;
CREATE POLICY "Kullanıcılar engelleyebilir"
  ON blocked_users FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = blocker_id 
    AND blocker_id != blocked_id
    AND blocker_id IS NOT NULL
    AND blocked_id IS NOT NULL
  );

-- support_tickets tablosu - Sadece kendi taleplerini görebilir
DROP POLICY IF EXISTS "Kullanıcılar kendi taleplerini görebilir" ON support_tickets;
CREATE POLICY "Kullanıcılar kendi taleplerini görebilir"
  ON support_tickets FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id AND user_id IS NOT NULL);

DROP POLICY IF EXISTS "Kullanıcılar talep oluşturabilir" ON support_tickets;
CREATE POLICY "Kullanıcılar talep oluşturabilir"
  ON support_tickets FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id AND user_id IS NOT NULL);

-- Admin güncellemesi için politika ekle
CREATE POLICY "Admin taleplerini güncelleyebilir"
  ON support_tickets FOR UPDATE
  USING (
    auth.uid() IN (
      SELECT id FROM profiles WHERE role = 'admin'
    )
  )
  WITH CHECK (
    auth.uid() IN (
      SELECT id FROM profiles WHERE role = 'admin'
    )
  );

-- 2. PERFORMANS - INDEX EKLEME
-- ============================================================================

-- Zaten var olanları kontrol et, yoksa ekle
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter_created 
  ON user_reports(reporter_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_reports_reported_created 
  ON user_reports(reported_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_blocked_users_blocker_created 
  ON blocked_users(blocker_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked_created 
  ON blocked_users(blocked_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_tickets_user_status 
  ON support_tickets(user_id, status);

CREATE INDEX IF NOT EXISTS idx_support_tickets_user_created 
  ON support_tickets(user_id, created_at DESC);

-- 3. PERFORMANS - MATERIALIZED VIEW İÇİN HELPER FUNCTION
-- ============================================================================

-- Engellenen kullanıcı bilgilerini hızlı çekmek için
CREATE OR REPLACE FUNCTION get_blocked_users_with_profiles(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  blocked_id UUID,
  created_at TIMESTAMPTZ,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    bu.id,
    bu.blocked_id,
    bu.created_at,
    pr.username,
    pr.full_name,
    pr.avatar_url
  FROM blocked_users bu
  LEFT JOIN profiles pr ON bu.blocked_id = pr.id
  WHERE bu.blocker_id = p_user_id
  ORDER BY bu.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION get_blocked_users_with_profiles(UUID) TO authenticated;

-- Şikayet edilen kullanıcı bilgilerini hızlı çekmek için
CREATE OR REPLACE FUNCTION get_my_reports_with_profiles(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  reported_user_id UUID,
  reason TEXT,
  description TEXT,
  status TEXT,
  created_at TIMESTAMPTZ,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ur.id,
    ur.reported_user_id,
    ur.reason,
    ur.description,
    ur.status,
    ur.created_at,
    pr.username,
    pr.full_name,
    pr.avatar_url
  FROM user_reports ur
  LEFT JOIN profiles pr ON ur.reported_user_id = pr.id
  WHERE ur.reporter_id = p_user_id
  ORDER BY ur.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION get_my_reports_with_profiles(UUID) TO authenticated;

-- 4. GÜVENLİK - DUPLICATE KONTROL CONSTRAINT
-- ============================================================================

-- Unique constraint zaten var, ancak trigger ile daha iyi kontrol ekle
CREATE OR REPLACE FUNCTION check_duplicate_report()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM user_reports 
    WHERE reporter_id = NEW.reporter_id 
      AND reported_user_id = NEW.reported_user_id
      AND status IN ('pending', 'reviewing')
  ) THEN
    RAISE EXCEPTION 'Bu kullanıcıyı zaten şikayet ettiniz';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_check_duplicate_report ON user_reports;
CREATE TRIGGER trigger_check_duplicate_report
  BEFORE INSERT ON user_reports
  FOR EACH ROW
  EXECUTE FUNCTION check_duplicate_report();

-- 5. GÜVENLİK - RATE LIMITING LOG TABLOSU
-- ============================================================================

CREATE TABLE IF NOT EXISTS report_rate_limit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action TEXT NOT NULL, -- 'report', 'block'
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_report_rate_limit_user_time 
  ON report_rate_limit(user_id, created_at DESC);

-- Rate limiting trigger (saatte 10 şikayet)
CREATE OR REPLACE FUNCTION check_rate_limit()
RETURNS TRIGGER AS $$
BEGIN
  IF (
    SELECT COUNT(*) FROM report_rate_limit
    WHERE user_id = NEW.reporter_id
      AND action = 'report'
      AND created_at > NOW() - INTERVAL '1 hour'
  ) >= 10 THEN
    RAISE EXCEPTION 'Çok fazla şikayet yaptınız. Lütfen daha sonra tekrar deneyin (1 saat sınırı)';
  END IF;
  
  INSERT INTO report_rate_limit (user_id, action) 
  VALUES (NEW.reporter_id, 'report');
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_check_rate_limit ON user_reports;
CREATE TRIGGER trigger_check_rate_limit
  BEFORE INSERT ON user_reports
  FOR EACH ROW
  EXECUTE FUNCTION check_rate_limit();

-- 6. VERİ TEMIZLIĞI - REDDEDILMIŞ ŞİKAYETLERİ OTOMATIK SİL (30 gün)
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_old_reports()
RETURNS void AS $$
BEGIN
  DELETE FROM user_reports
  WHERE status = 'rejected'
    AND created_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- 7. AUDIT LOG TABLOSU
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name TEXT NOT NULL,
  action TEXT NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
  user_id UUID REFERENCES auth.users(id),
  changed_data JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_user_created 
  ON audit_log(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_table_created 
  ON audit_log(table_name, created_at DESC);

-- Şikayetler için audit log
CREATE OR REPLACE FUNCTION audit_user_reports()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (table_name, action, user_id, changed_data)
  VALUES (
    'user_reports',
    TG_OP,
    COALESCE(NEW.reporter_id, OLD.reporter_id),
    CASE 
      WHEN TG_OP = 'DELETE' THEN row_to_json(OLD)
      ELSE row_to_json(NEW)
    END
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_audit_user_reports ON user_reports;
CREATE TRIGGER trigger_audit_user_reports
  AFTER INSERT OR UPDATE OR DELETE ON user_reports
  FOR EACH ROW
  EXECUTE FUNCTION audit_user_reports();

-- 8. RLS - AUDIT LOG İÇİN
-- ============================================================================

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Sadece admin'ler audit log'u görebilir
CREATE POLICY "Admin audit log'u görebilir"
  ON audit_log FOR SELECT
  TO authenticated
  USING (
    auth.uid() IN (SELECT id FROM profiles WHERE role = 'admin')
  );

-- 9. SONUÇ
-- ============================================================================

SELECT 'Güvenlik ve performans iyileştirmeleri tamamlandı!' as result;

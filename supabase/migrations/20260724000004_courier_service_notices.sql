-- Kurye servisi uyarı ve duyurularını yönetmek için
CREATE TABLE IF NOT EXISTS courier_service_notices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  notice_type VARCHAR(50) DEFAULT 'info', -- info, warning, alert, success
  priority INTEGER DEFAULT 0, -- 0: normal, 1: high, 2: urgent
  is_active BOOLEAN DEFAULT true,
  show_on_send_package_screen BOOLEAN DEFAULT true,
  show_on_courier_panel BOOLEAN DEFAULT true,
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- İndeksler
CREATE INDEX idx_courier_service_notices_active ON courier_service_notices(is_active, show_on_send_package_screen)
  WHERE is_active = true;
CREATE INDEX idx_courier_service_notices_dates ON courier_service_notices(start_date, end_date)
  WHERE is_active = true;

-- Enable Realtime
DO $$
BEGIN
  EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE courier_service_notices';
EXCEPTION WHEN duplicate_object THEN
  NULL;
END;
$$;

-- RLS Policies
ALTER TABLE courier_service_notices ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir (sadece aktif olanlar)
CREATE POLICY "courier_notices_public_read" ON courier_service_notices
  FOR SELECT USING (
    is_active = true
    AND (start_date IS NULL OR start_date <= NOW())
    AND (end_date IS NULL OR end_date >= NOW())
  );

-- Sadece admin yaz/sil
CREATE POLICY "courier_notices_admin_write" ON courier_service_notices
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Trigger: updated_at otomatik güncelle
CREATE OR REPLACE FUNCTION update_courier_service_notices_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_courier_service_notices_timestamp ON courier_service_notices;
CREATE TRIGGER trigger_update_courier_service_notices_timestamp
BEFORE UPDATE ON courier_service_notices
FOR EACH ROW
EXECUTE FUNCTION update_courier_service_notices_timestamp();

-- Örnek veri (test için)
INSERT INTO courier_service_notices (title, message, notice_type, priority, show_on_send_package_screen, show_on_courier_panel, is_active)
VALUES (
  'Kurye Servisi Açık',
  'Kurye servisi aktif ve çalışmaktadır. Hızlı ve güvenli teslimat için bize güvenin.',
  'success',
  0,
  true,
  true,
  false -- Başta deaktif, admin aktive edecek
)
ON CONFLICT DO NOTHING;

DO $$ BEGIN
  RAISE NOTICE '✅ 20260724000004 — Kurye servisi uyarıları tablosu oluşturuldu';
END $$;

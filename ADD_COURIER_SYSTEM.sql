-- ============================================
-- KURYE SİSTEMİ TABLOLARI
-- ============================================

-- 1. Kurye ayarları tablosu (pakat başı ücret vb.)
CREATE TABLE IF NOT EXISTS courier_settings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  fee_per_delivery NUMERIC(10, 2) DEFAULT 15.00,  -- Paket başı ücret (₺)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Varsayılan ayar ekle
INSERT INTO courier_settings (fee_per_delivery)
VALUES (15.00)
ON CONFLICT DO NOTHING;

-- 2. Kurye sipariş atamaları tablosu
CREATE TABLE IF NOT EXISTS courier_assignments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  courier_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'assigned',  -- assigned, picked_up, delivered, cancelled
  fee_amount NUMERIC(10, 2) DEFAULT 0,  -- Bu sipariş için kurye ücreti
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  picked_up_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  cancellation_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(order_id, courier_id)
);

-- 3. Kurye kazanç takibi
CREATE TABLE IF NOT EXISTS courier_earnings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  courier_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  assignment_id UUID REFERENCES courier_assignments(id) ON DELETE SET NULL,
  order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
  amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
  status TEXT DEFAULT 'pending',  -- pending, paid, cancelled
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Kurye profil istatistikleri için (opsiyonel - profilde counter tutmak yerine)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS delivered_count INTEGER DEFAULT 0;

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_courier_assignments_courier_id ON courier_assignments(courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_assignments_order_id ON courier_assignments(order_id);
CREATE INDEX IF NOT EXISTS idx_courier_assignments_status ON courier_assignments(status);
CREATE INDEX IF NOT EXISTS idx_courier_earnings_courier_id ON courier_earnings(courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_earnings_status ON courier_earnings(status);

-- RLS Politikaları
ALTER TABLE courier_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE courier_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE courier_earnings ENABLE ROW LEVEL SECURITY;

-- courier_settings: herkes okuyabilir, sadece admin yazabilir
CREATE POLICY "Courier settings okuma" ON courier_settings
  FOR SELECT USING (true);

CREATE POLICY "Courier settings admin yazma" ON courier_settings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- courier_assignments: kuryeler kendi atamalarını görebilir, admin hepsini görebilir
CREATE POLICY "Courier assignments kurye okuma" ON courier_assignments
  FOR SELECT USING (
    courier_id = auth.uid() OR
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Courier assignments kurye yazma" ON courier_assignments
  FOR INSERT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'courier'))
  );

CREATE POLICY "Courier assignments kurye güncelleme" ON courier_assignments
  FOR UPDATE USING (
    courier_id = auth.uid() OR
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- courier_earnings: kuryeler kendi kazançlarını görebilir, admin hepsini
CREATE POLICY "Courier earnings kurye okuma" ON courier_earnings
  FOR SELECT USING (
    courier_id = auth.uid() OR
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Courier earnings admin yazma" ON courier_earnings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );
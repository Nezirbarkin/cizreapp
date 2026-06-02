-- ============================================
-- COURIER_SETTINGS RLS POLITIKALARI
-- Supabase SQL Editor'de calistirin
-- ============================================

-- RLS etkinlestir
ALTER TABLE courier_settings ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir (kurye ucretini herkes gorebilmeli)
CREATE POLICY "Anyone can read courier settings"
  ON courier_settings
  FOR SELECT
  USING (true);

-- Sadece admin yazabilir
CREATE POLICY "Admins can insert courier settings"
  ON courier_settings
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = (select auth.uid()) AND role = 'admin'
    )
  );

CREATE POLICY "Admins can update courier settings"
  ON courier_settings
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = (select auth.uid()) AND role = 'admin'
    )
  );

-- Mevcut kayıt yoksa bir tane ekle (INSERT AFTER RLS)
INSERT INTO courier_settings (fee_per_delivery) VALUES (15.0) ON CONFLICT DO NOTHING;
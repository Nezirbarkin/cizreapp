-- ============================================
-- KURYE ODEME ISTEKLERI TABLOSU
-- Supabase SQL Editor'de calistirin
-- ============================================

-- 1. Kurye odeme istekleri tablosu
CREATE TABLE IF NOT EXISTS courier_payout_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  courier_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  amount DOUBLE PRECISION NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'paid', 'rejected')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. RLS politikaları
ALTER TABLE courier_payout_requests ENABLE ROW LEVEL SECURITY;

-- Kuryeler sadece kendi odeme isteklerini gorebilir
CREATE POLICY "Couriers can view own payout requests"
  ON courier_payout_requests
  FOR SELECT
  USING (courier_id = auth.uid());

-- Adminler tum odeme isteklerini gorebilir
CREATE POLICY "Admins can view all payout requests"
  ON courier_payout_requests
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Kuryeler odeme istegi olusturabilir
CREATE POLICY "Couriers can create payout requests"
  ON courier_payout_requests
  FOR INSERT
  WITH CHECK (courier_id = auth.uid());

-- Adminler odeme isteklerini onaylayabilir
CREATE POLICY "Admins can update payout requests"
  ON courier_payout_requests
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 3. Kurye kazançlari tablosu (yoksa olustur)
CREATE TABLE IF NOT EXISTS courier_earnings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  courier_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  assignment_id UUID REFERENCES courier_assignments(id) ON DELETE SET NULL,
  order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
  amount DOUBLE PRECISION NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'requested', 'paid')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Kurye kazançlari RLS
ALTER TABLE courier_earnings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Couriers can view own earnings"
  ON courier_earnings
  FOR SELECT
  USING (courier_id = auth.uid());

CREATE POLICY "Admins can view all earnings"
  ON courier_earnings
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 5. profiles tablosuna is_online ve delivered_count kolonlari (yoksa ekle)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'is_online'
  ) THEN
    ALTER TABLE profiles ADD COLUMN is_online BOOLEAN DEFAULT true;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'delivered_count'
  ) THEN
    ALTER TABLE profiles ADD COLUMN delivered_count INTEGER DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'fcm_token'
  ) THEN
    ALTER TABLE profiles ADD COLUMN fcm_token TEXT;
  END IF;
END $$;

-- 6. Index'ler
CREATE INDEX IF NOT EXISTS idx_courier_payout_requests_courier ON courier_payout_requests(courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_payout_requests_status ON courier_payout_requests(status);
CREATE INDEX IF NOT EXISTS idx_courier_earnings_courier ON courier_earnings(courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_earnings_status ON courier_earnings(status);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);
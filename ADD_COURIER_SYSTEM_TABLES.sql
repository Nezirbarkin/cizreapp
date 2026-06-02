-- ============================================
-- KURYE SISTEMI - TEMEL TABLOLAR
-- Supabase SQL Editor'de sirasiyla calistirin
-- ============================================

-- 1. courier_settings tablosu (kurye ucret ayarlari)
CREATE TABLE IF NOT EXISTS courier_settings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  fee_per_delivery DOUBLE PRECISION NOT NULL DEFAULT 15.0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Varsayilan ayar ekle
INSERT INTO courier_settings (fee_per_delivery) VALUES (15.0) ON CONFLICT DO NOTHING;

-- 2. courier_assignments tablosu (siparis-kurye atamalari)
CREATE TABLE IF NOT EXISTS courier_assignments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  courier_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'assigned' CHECK (status IN ('assigned', 'picked_up', 'delivered', 'cancelled')),
  fee_amount DOUBLE PRECISION NOT NULL DEFAULT 0,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  picked_up_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(order_id, courier_id)
);

-- 3. RLS politikaları - courier_assignments
ALTER TABLE courier_assignments ENABLE ROW LEVEL SECURITY;

-- Kuryeler kendi atamalarini gorebilir
CREATE POLICY "Couriers can view own assignments"
  ON courier_assignments
  FOR SELECT
  USING (courier_id = auth.uid());

-- Satıcılar kendi siparislerinin atamalarini gorebilir
CREATE POLICY "Sellers can view own order assignments"
  ON courier_assignments
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM orders o
      JOIN shops s ON o.shop_id = s.id
      WHERE o.id = courier_assignments.order_id AND s.owner_id = auth.uid()
    )
  );

-- Adminler tum atamalari gorebilir
CREATE POLICY "Admins can view all assignments"
  ON courier_assignments
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Kuryeler atama olusturabilir (siparis alma)
CREATE POLICY "Couriers can create assignments"
  ON courier_assignments
  FOR INSERT
  WITH CHECK (courier_id = auth.uid());

-- Kuryeler kendi atamalarini guncelleyebilir
CREATE POLICY "Couriers can update own assignments"
  ON courier_assignments
  FOR UPDATE
  USING (courier_id = auth.uid());

-- 4. courier_payout_requests tablosu (kurye odeme istekleri)
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

-- 5. RLS - courier_payout_requests
ALTER TABLE courier_payout_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Couriers can view own payout requests"
  ON courier_payout_requests
  FOR SELECT
  USING (courier_id = auth.uid());

CREATE POLICY "Admins can view all payout requests"
  ON courier_payout_requests
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Couriers can create payout requests"
  ON courier_payout_requests
  FOR INSERT
  WITH CHECK (courier_id = auth.uid());

CREATE POLICY "Admins can update payout requests"
  ON courier_payout_requests
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 6. courier_earnings tablosu (kurye kazançlari)
CREATE TABLE IF NOT EXISTS courier_earnings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  courier_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  assignment_id UUID REFERENCES courier_assignments(id) ON DELETE SET NULL,
  order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
  amount DOUBLE PRECISION NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'requested', 'paid')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. RLS - courier_earnings
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

CREATE POLICY "Couriers can insert own earnings"
  ON courier_earnings
  FOR INSERT
  WITH CHECK (courier_id = auth.uid());

CREATE POLICY "Admins can update earnings"
  ON courier_earnings
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 8. profiles tablosuna ek kolonlar
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

-- 9. Index'ler
CREATE INDEX IF NOT EXISTS idx_courier_assignments_courier ON courier_assignments(courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_assignments_order ON courier_assignments(order_id);
CREATE INDEX IF NOT EXISTS idx_courier_assignments_status ON courier_assignments(status);
CREATE INDEX IF NOT EXISTS idx_courier_payout_requests_courier ON courier_payout_requests(courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_payout_requests_status ON courier_payout_requests(status);
CREATE INDEX IF NOT EXISTS idx_courier_earnings_courier ON courier_earnings(courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_earnings_status ON courier_earnings(status);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);
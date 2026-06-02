-- ============================================
-- KURYE ODEME BILGILERI TABLOSU
-- Supabase SQL Editor'de calistirin
-- ============================================

-- 1. Kurye odeme bilgileri tablosu
CREATE TABLE IF NOT EXISTS courier_payment_info (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  courier_id UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  iban TEXT NOT NULL,
  bank_name TEXT,
  account_holder_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. RLS politikaları
ALTER TABLE courier_payment_info ENABLE ROW LEVEL SECURITY;

-- Kuryeler kendi odeme bilgilerini gorebilir
CREATE POLICY "Couriers view own payment info"
  ON courier_payment_info
  FOR SELECT
  USING (courier_id = (select auth.uid()));

-- Kuryeler kendi odeme bilgilerini olusturabilir
CREATE POLICY "Couriers insert own payment info"
  ON courier_payment_info
  FOR INSERT
  WITH CHECK (courier_id = (select auth.uid()));

-- Kuryeler kendi odeme bilgilerini guncelleyebilir
CREATE POLICY "Couriers update own payment info"
  ON courier_payment_info
  FOR UPDATE
  USING (courier_id = (select auth.uid()));

-- Adminler tum odeme bilgilerini gorebilir
CREATE POLICY "Admins view all payment info"
  ON courier_payment_info
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = (select auth.uid()) AND role = 'admin'
    )
  );

-- 3. Index
CREATE INDEX IF NOT EXISTS idx_courier_payment_info_courier ON courier_payment_info(courier_id);
-- ============================================
-- KURYE RLS POLITIKALARINI OPTIMIZE ET
-- auth.uid() -> (select auth.uid()) degisimi
-- Supabase SQL Editor'de calistirin
-- ============================================

-- ONCEKI POLITIKALARI SIL
DROP POLICY IF EXISTS "Couriers can view own assignments" ON courier_assignments;
DROP POLICY IF EXISTS "Sellers can view own order assignments" ON courier_assignments;
DROP POLICY IF EXISTS "Admins can view all assignments" ON courier_assignments;
DROP POLICY IF EXISTS "Couriers can create assignments" ON courier_assignments;
DROP POLICY IF EXISTS "Couriers can update own assignments" ON courier_assignments;

DROP POLICY IF EXISTS "Couriers can view own payout requests" ON courier_payout_requests;
DROP POLICY IF EXISTS "Admins can view all payout requests" ON courier_payout_requests;
DROP POLICY IF EXISTS "Couriers can create payout requests" ON courier_payout_requests;
DROP POLICY IF EXISTS "Admins can update payout requests" ON courier_payout_requests;

DROP POLICY IF EXISTS "Couriers can view own earnings" ON courier_earnings;
DROP POLICY IF EXISTS "Admins can view all earnings" ON courier_earnings;
DROP POLICY IF EXISTS "Couriers can insert own earnings" ON courier_earnings;
DROP POLICY IF EXISTS "Admins can update earnings" ON courier_earnings;

-- OPTIMIZE EDILMIS POLITIKALAR (select auth.uid() ile)
-- courier_assignments
CREATE POLICY "Couriers view own assignments" ON courier_assignments
  FOR SELECT USING (courier_id = (select auth.uid()));

CREATE POLICY "Sellers view own order assignments" ON courier_assignments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM orders o
      JOIN shops s ON o.shop_id = s.id
      WHERE o.id = courier_assignments.order_id AND s.owner_id = (select auth.uid())
    )
  );

CREATE POLICY "Admins view all assignments" ON courier_assignments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = (select auth.uid()) AND role = 'admin'
    )
  );

CREATE POLICY "Couriers create assignments" ON courier_assignments
  FOR INSERT WITH CHECK (courier_id = (select auth.uid()));

CREATE POLICY "Couriers update own assignments" ON courier_assignments
  FOR UPDATE USING (courier_id = (select auth.uid()));

-- courier_payout_requests
CREATE POLICY "Couriers view own payouts" ON courier_payout_requests
  FOR SELECT USING (courier_id = (select auth.uid()));

CREATE POLICY "Admins view all payouts" ON courier_payout_requests
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = (select auth.uid()) AND role = 'admin'
    )
  );

CREATE POLICY "Couriers create payouts" ON courier_payout_requests
  FOR INSERT WITH CHECK (courier_id = (select auth.uid()));

CREATE POLICY "Admins update payouts" ON courier_payout_requests
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = (select auth.uid()) AND role = 'admin'
    )
  );

-- courier_earnings
CREATE POLICY "Couriers view own earnings" ON courier_earnings
  FOR SELECT USING (courier_id = (select auth.uid()));

CREATE POLICY "Admins view all earnings" ON courier_earnings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = (select auth.uid()) AND role = 'admin'
    )
  );

CREATE POLICY "Couriers insert own earnings" ON courier_earnings
  FOR INSERT WITH CHECK (courier_id = (select auth.uid()));

CREATE POLICY "Admins update earnings" ON courier_earnings
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = (select auth.uid()) AND role = 'admin'
    )
  );
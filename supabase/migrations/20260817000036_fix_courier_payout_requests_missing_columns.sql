-- =============================================================================
-- courier_payout_requests: eksik kolonlari geri yukle (prod desync duzeltmesi)
--
-- 20260802000005_secure_courier_delivery_and_payout.sql tabloya approved_by,
-- rejected_at, rejection_reason, payment_reference kolonlarini eklemesi
-- gerekiyordu (ADD COLUMN IF NOT EXISTS ile). supabase_migrations.schema_migrations
-- gecmisi bu projede local migrations/ klasoruyle senkron degil (bkz. proje notlari);
-- bu ALTER TABLE adimi prod'da hic calismamis. Sonuc: admin_approve_courier_payout
-- ve admin_reject_courier_payout fonksiyonlari (20260817000018/19) bu kolonlara
-- UPDATE atmaya calisiyor ve admin panelinde "column approved_by does not exist"
-- (42703) hatasi ile odeme onayi/reddi tamamen basarisiz oluyor.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.courier_payout_requests
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS payment_reference text;

NOTIFY pgrst, 'reload schema';

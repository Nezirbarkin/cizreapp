-- ============================================================================
-- VERIFICATION CODE TYPE FIX
-- ============================================================================
-- 'order_verification' type'ını desteklemek için CHECK constraint güncelleme
-- ============================================================================

-- Önce eski CHECK constraint'i kaldır
ALTER TABLE public.verification_codes DROP CONSTRAINT IF EXISTS verification_codes_code_type_check;

-- Yeni CHECK constraint'i ekle (order_verification dahil)
ALTER TABLE public.verification_codes 
  ADD CONSTRAINT verification_codes_code_type_check 
  CHECK (code_type IN ('order_verification', 'order_confirmation', 'email_verification', 'password_reset'));

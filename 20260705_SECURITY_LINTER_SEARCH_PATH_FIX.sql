-- ============================================================================
-- 20260705_SECURITY_LINTER_SEARCH_PATH_FIX.sql
-- ============================================================================
-- Amaç: Supabase Database Linter uyarısı: `function_search_path_mutable`.
--       8 fonksiyon `SET search_path` kullanmıyor → saldırgan search_path'i
--       değiştirip yetkisiz şemalardan fonksiyon çağırabilir.
--
-- Düzeltme: Her fonksiyona `SET search_path = public, pg_temp` ekle.
-- Bu tamamen güvenli bir değişiklik:
-- - Mevcut davranış değişmez (zaten public semasında çalışıyorlardı)
-- - Flutter tarafı etkilenmez (sadece metadata değişir)
-- - Edge functions etkilenmez
-- - Trigger'lar etkilenmez (zaten SECURITY DEFINER context)
--
-- Idempotent: ALTER FUNCTION SET search_path birden fazla çalıştırılabilir.
-- Diğer linter uyarıları (RLS always_true, anon SECURITY DEFINER, public
-- bucket listing, auth_leaked_password) bilerek sonraya bırakıldı.
-- ============================================================================

BEGIN;

-- 1. update_seller_earnings_timestamp
ALTER FUNCTION public.update_seller_earnings_timestamp()
  SET search_path = public, pg_temp;

-- 2. update_user_balances_timestamp
ALTER FUNCTION public.update_user_balances_timestamp()
  SET search_path = public, pg_temp;

-- 3. update_seller_withdrawals_timestamp
ALTER FUNCTION public.update_seller_withdrawals_timestamp()
  SET search_path = public, pg_temp;

-- 4. update_profile_fields
ALTER FUNCTION public.update_profile_fields()
  SET search_path = public, pg_temp;

-- 5. create_seller_earnings_on_delivery
ALTER FUNCTION public.create_seller_earnings_on_delivery()
  SET search_path = public, pg_temp;

-- 6. add_to_balance (HAVALE ONAY akışında çağrılır — kritik)
ALTER FUNCTION public.add_to_balance(
  p_user_id UUID,
  p_amount DECIMAL,
  p_type balance_transaction_type,
  p_reference_type VARCHAR,
  p_reference_id UUID,
  p_description TEXT,
  p_payment_method VARCHAR,
  p_payment_reference VARCHAR,
  p_metadata JSONB
) SET search_path = public, pg_temp;

-- 7. deduct_from_balance
ALTER FUNCTION public.deduct_from_balance(
  p_user_id UUID,
  p_amount DECIMAL,
  p_type balance_transaction_type,
  p_reference_type VARCHAR,
  p_reference_id UUID,
  p_description TEXT,
  p_metadata JSONB
) SET search_path = public, pg_temp;

-- 8. create_user_balance_on_signup
ALTER FUNCTION public.create_user_balance_on_signup()
  SET search_path = public, pg_temp;

COMMIT;

-- ============================================================================
-- DOĞRULAMA: linter tekrar tarayacak, bu 8 fonksiyon artık uyarı vermemeli.
-- Manuel kontrol:
-- SELECT proname, proconfig
-- FROM pg_proc
-- WHERE proname IN (
--   'update_seller_earnings_timestamp','update_user_balances_timestamp',
--   'update_seller_withdrawals_timestamp','update_profile_fields',
--   'create_seller_earnings_on_delivery','add_to_balance','deduct_from_balance',
--   'create_user_balance_on_signup'
-- )
-- AND pronamespace = 'public'::regnamespace;
-- proconfig kolonunda "{search_path=public, pg_temp}" görmeli.
-- ============================================================================
-- =============================================================================
-- Kritik bakiye RPC yetkilerini daralt
-- =============================================================================
-- add_to_balance rastgele p_user_id/p_amount kabul ettiği için hiçbir istemci
-- rolü tarafından doğrudan çağrılamaz. Yalnız Edge Functions ve güvenli iç DB
-- akışları için service_role erişimi korunur.
--
-- deduct_from_balance istemci tarafından paket gönderiminde kullanılır. Bu
-- nedenle authenticated erişimi korunur; ancak fonksiyon kullanıcının yalnızca
-- kendi bakiyesinden düşebilmesini ve izinli işlem tipini zorunlu kılar.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) add_to_balance: yalnız service_role
-- -----------------------------------------------------------------------------
DO $migration$
DECLARE
  v_function regprocedure;
BEGIN
  FOR v_function IN
    SELECT p.oid::regprocedure
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'add_to_balance'
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      v_function
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION %s TO service_role',
      v_function
    );
  END LOOP;
END
$migration$;

-- -----------------------------------------------------------------------------
-- 2) deduct_from_balance: authenticated yalnız kendi kurye ödemesini yapabilir
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.deduct_from_balance(
  p_user_id uuid,
  p_amount numeric,
  p_type public.balance_transaction_type,
  p_reference_type character varying,
  p_reference_id uuid,
  p_description text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE(
  transaction_id uuid,
  balance_before numeric,
  balance_after numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_role text := COALESCE(auth.role(), '');
  v_balance_id uuid;
  v_current_balance numeric(12, 2);
  v_balance_before numeric(12, 2);
  v_balance_after numeric(12, 2);
  v_transaction_id uuid;
BEGIN
  IF p_user_id IS NULL OR p_reference_id IS NULL THEN
    RAISE EXCEPTION 'Kullanıcı ve referans kimliği zorunludur';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 100000 THEN
    RAISE EXCEPTION 'Geçersiz işlem tutarı';
  END IF;

  -- service_role; sipariş, SMM ve sunucu akışlarında tüm desteklenen tipleri
  -- kullanabilir. İstemci rolü yalnız kendi paket gönderim ücretini düşebilir.
  IF v_caller_role <> 'service_role' THEN
    IF (SELECT auth.uid()) IS NULL OR p_user_id IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'Başka bir kullanıcı adına bakiye düşürülemez';
    END IF;

    IF p_type::text <> 'courier_payment'
       OR p_reference_type IS DISTINCT FROM 'courier_request' THEN
      RAISE EXCEPTION 'İstemci için desteklenmeyen bakiye işlemi';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.courier_requests AS cr
      WHERE cr.id = p_reference_id
        AND cr.sender_id = (SELECT auth.uid())
        AND cr.status = 'pending'
        AND cr.total_fee IS NOT NULL
        AND round(cr.total_fee::numeric, 2) = round(p_amount::numeric, 2)
    ) THEN
      RAISE EXCEPTION 'Paket talebi veya ücret doğrulanamadı';
    END IF;
  END IF;

  SELECT ub.id, ub.balance
  INTO v_balance_id, v_current_balance
  FROM public.user_balances AS ub
  WHERE ub.user_id = p_user_id
  FOR UPDATE;

  IF v_balance_id IS NULL THEN
    RAISE EXCEPTION 'Kullanıcı bakiye kaydı bulunamadı';
  END IF;

  IF v_current_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient balance. Available: %, Required: %',
      v_current_balance, p_amount;
  END IF;

  v_balance_before := v_current_balance;
  v_balance_after := v_current_balance - p_amount;

  UPDATE public.user_balances AS ub
  SET balance = v_balance_after,
      total_spent = ub.total_spent + p_amount,
      updated_at = now()
  WHERE ub.id = v_balance_id;

  INSERT INTO public.balance_transactions (
    user_id,
    type,
    amount,
    net_amount,
    balance_before,
    balance_after,
    reference_type,
    reference_id,
    status,
    description,
    metadata
  ) VALUES (
    p_user_id,
    p_type,
    p_amount,
    p_amount,
    v_balance_before,
    v_balance_after,
    p_reference_type,
    p_reference_id,
    'completed',
    p_description,
    p_metadata
  )
  RETURNING id INTO v_transaction_id;

  RETURN QUERY
  SELECT v_transaction_id, v_balance_before, v_balance_after;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.deduct_from_balance(
  uuid, numeric, public.balance_transaction_type, character varying, uuid, text, jsonb
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.deduct_from_balance(
  uuid, numeric, public.balance_transaction_type, character varying, uuid, text, jsonb
) TO authenticated, service_role;

COMMENT ON FUNCTION public.deduct_from_balance(
  uuid, numeric, public.balance_transaction_type, character varying, uuid, text, jsonb
) IS
  'Atomik bakiye düşümü. Authenticated yalnız kendi doğrulanmış courier_request ücretini; service_role sunucu işlemlerini çalıştırabilir.';

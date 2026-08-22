-- ============================================================================
-- 20260707000000_DEDUCT_FROM_BALANCE_ENRICHED.sql
-- ----------------------------------------------------------------------------
-- Sorun: deduct_from_balance RPC RETURNS uuid (scalar) — sadece transaction_id
-- döndürüyor. Edge function use-balance-for-order ise RETURNS TABLE bekliyor
-- (row.transaction_id, row.balance_after). Bu yüzden balance_after null geliyor
-- ve Dart tarafı (eski halinde) 'as num)' cast'inde patlıyordu.
--
-- Düzeltme: 20260628000000_enrich_deduct_from_balance_rpc.sql migration'ı bunu
-- yapıyordu ama DB'ye hiç uygulanmamış. Bu migration aynı şeyi yapar + GRANT
-- satırlarını ekler (DROP ile birlikte silinen yetkileri yeniden verir).
-- ============================================================================

DROP FUNCTION IF EXISTS public.deduct_from_balance(
    UUID, DECIMAL, balance_transaction_type, VARCHAR, UUID, TEXT, JSONB
);

CREATE FUNCTION public.deduct_from_balance(
    p_user_id UUID,
    p_amount DECIMAL(12, 2),
    p_type balance_transaction_type,
    p_reference_type VARCHAR,
    p_reference_id UUID,
    p_description TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::JSONB
)
RETURNS TABLE(
    transaction_id UUID,
    balance_before NUMERIC,
    balance_after NUMERIC
) AS $$
DECLARE
    v_balance_id UUID;
    v_current_balance DECIMAL(12, 2);
    v_balance_before DECIMAL(12, 2);
    v_balance_after DECIMAL(12, 2);
    v_transaction_id UUID;
BEGIN
    -- Yeterli bakiye kontrolü (satır kilidi al, race condition önleme)
    SELECT id, balance INTO v_balance_id, v_current_balance
    FROM public.user_balances
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF v_balance_id IS NULL THEN
        RAISE EXCEPTION 'Balance record not found for user';
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance. Available: %, Required: %', v_current_balance, p_amount;
    END IF;

    v_balance_before := v_current_balance;
    v_balance_after := v_current_balance - p_amount;

    -- Bakiyeyi güncelle
    UPDATE public.user_balances
    SET balance = v_balance_after,
        total_spent = total_spent + p_amount,
        updated_at = NOW()
    WHERE id = v_balance_id;

    -- İşlem kaydı oluştur
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
    ) RETURNING id INTO v_transaction_id;

    RETURN QUERY SELECT v_transaction_id, v_balance_before, v_balance_after;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- DROP FUNCTION ile silinen yetkileri yeniden ver.
-- authenticated (kullanıcılar) Edge function üzerinden çağırır.
-- service_role (Edge function) bypass zaten ediyor, yine de açıkça verelim.
GRANT EXECUTE ON FUNCTION public.deduct_from_balance(
    UUID, DECIMAL, balance_transaction_type, VARCHAR, UUID, TEXT, JSONB
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deduct_from_balance(
    UUID, DECIMAL, balance_transaction_type, VARCHAR, UUID, TEXT, JSONB
) TO service_role;
GRANT EXECUTE ON FUNCTION public.deduct_from_balance(
    UUID, DECIMAL, balance_transaction_type, VARCHAR, UUID, TEXT, JSONB
) TO anon;

COMMENT ON FUNCTION public.deduct_from_balance IS
'Kullanıcı bakiyesinden atomik düşürme (FOR UPDATE lock). Yetersiz bakiyede raise exception. Dönüş: transaction_id, balance_before, balance_after.';
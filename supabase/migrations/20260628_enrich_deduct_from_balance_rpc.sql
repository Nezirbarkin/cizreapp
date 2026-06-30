-- =====================================================================
-- deduct_from_balance RPC dönüş tipini zenginleştir
-- ---------------------------------------------------------------------
-- Önceki sürüm sadece transaction_id (UUID) dönüyordu. Bu, çağıran
-- (Edge Function use-balance-for-order) tarafından balance_before /
-- balance_after bilgilerini almak için ikinci bir SELECT yapılmasını
-- zorunlu kılıyordu ve bilgilendirme amaçlı balance_after değeri
-- eşzamanlı işlemler nedeniyle tutarsız olabilirdy.
--
-- Bu migration RPC'yi RETURNS TABLE(...) yapar: tek çağrı, atomik
-- düşürme + transaction kaydı + balance öncesi/sonrası bilgisi.
-- FOR UPDATE lock zaten mevcut (race condition koruması).
--
-- Güvenlik: Parametre signature'ı aynı; sadece dönüş tipi değişti.
-- Mevcut tek çağıran use-balance-for-order/index.ts olduğundan geriye
-- dönük uyumluluk riski yoktur.
-- =====================================================================

-- PostgreSQL bir fonksiyonun dönüş tipini CREATE OR REPLACE ile değiştiremez.
-- Bu yüzden önce mevcut fonksiyonu (RETURNS UUID) DROP ediyoruz.
-- GRANT'lar DROP FUNCTION ile birlikte kaybolur; sonra yeniden veriyoruz.
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
    -- Yeterli bakiye kontrolü (satır kilidi al, race condition önle)
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

COMMENT ON FUNCTION public.deduct_from_balance IS
'Kullanıcı bakiyesinden atomik düşürme (FOR UPDATE lock). Yetersiz bakiyede raise exception. Dönüş: transaction_id, balance_before, balance_after.';
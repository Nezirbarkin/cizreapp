-- ============================================================================
-- BAKİYE TUTARSIZLIĞI DÜZELTME
-- ----------------------------------------------------------------------------
-- Sorun: add_to_balance RPC'si refund (iade) işlemlerinde total_earned'a ekliyor.
--         Bu yanlış — iade para kazanma değil, sadece geri dönüş.
--         Sonuç: yüklenen + iade = harcanan + bakiye  ✓  olması gerekirken
--                yüklenen = harcanan + bakiye - iade    ✗  oluyordu
--
-- Düzeltme:
--   1) user_balances tablosuna total_refunds sütunu eklenir
--   2) add_to_balance RPC'sinde:
--        type='refund' → total_refunds += amount (total_earned DEĞİL)
--   3) admin_user_spending_summary view'ına total_refunds ve iade_sayisi eklenir
--      (toplam harcama ayrı, iadeler ayrı görünür)
--
-- DENKLEM (düzeltme sonrası):
--   bakiye = (yüklenen) - (harcanan) + (iade edilen) - (çekilen)
--          = total_topups - total_spent + total_refunds - total_withdrawn
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) user_balances tablosuna total_refunds sütunu ekle
-- ---------------------------------------------------------------------------
ALTER TABLE public.user_balances
    ADD COLUMN IF NOT EXISTS total_refunds DECIMAL(12, 2) NOT NULL DEFAULT 0.00;

COMMENT ON COLUMN public.user_balances.total_refunds IS
'Bu kullanıcıya yapılan toplam iade tutarı (refund). Bakiye hesabında
toplam_yuklenen - toplam_harcanan + toplam_iade - toplam_cekim olarak kullanılır.';

-- ---------------------------------------------------------------------------
-- 2) add_to_balance RPC'sini güncelle: refund'da total_earned yerine total_refunds
-- ---------------------------------------------------------------------------
-- Mevcut fonksiyonu REPLACE ediyoruz (sadece refund bloğunu değiştiriyoruz).
-- DIKKAT: Fonksiyon gövdesinin tamamını veriyoruz, eski ile karşılaştırarak
-- sadece 3 satırlık farkı göreceksiniz (total_earned → total_refunds).
CREATE OR REPLACE FUNCTION add_to_balance(
    p_user_id UUID,
    p_amount DECIMAL(12, 2),
    p_type balance_transaction_type,
    p_reference_type VARCHAR,
    p_reference_id UUID,
    p_description TEXT DEFAULT NULL,
    p_payment_method VARCHAR DEFAULT NULL,
    p_payment_reference VARCHAR DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::JSONB
)
RETURNS UUID AS $$
DECLARE
    v_balance_id UUID;
    v_balance_before DECIMAL(12, 2);
    v_balance_after DECIMAL(12, 2);
    v_transaction_id UUID;
BEGIN
    -- Kullanıcının bakiyesini bul veya oluştur
    SELECT id, balance INTO v_balance_id, v_balance_before
    FROM user_balances
    WHERE user_id = p_user_id;

    IF v_balance_id IS NULL THEN
        INSERT INTO user_balances (user_id, balance)
        VALUES (p_user_id, 0)
        RETURNING id, balance INTO v_balance_id, v_balance_before;
    END IF;

    -- Yeni bakiyeyi hesapla
    v_balance_after := v_balance_before + p_amount;

    -- Bakiyeyi güncelle
    -- ÖNEMLİ: refund işlemlerinde total_earned'a DEĞİL total_refunds'a ekle!
    -- total_earned = gerçek kazanç (toplam yükleme, bonus vb.)
    -- total_refunds = yapılan iadelerin toplamı (satıcı/iade kaynaklı)
    IF p_type = 'refund'::balance_transaction_type THEN
        UPDATE user_balances
        SET balance       = v_balance_after,
            total_refunds = total_refunds + p_amount,
            updated_at    = NOW()
        WHERE id = v_balance_id;
    ELSE
        UPDATE user_balances
        SET balance       = v_balance_after,
            total_earned  = total_earned + p_amount,
            updated_at    = NOW()
        WHERE id = v_balance_id;
    END IF;

    -- İşlem kaydı oluştur
    INSERT INTO balance_transactions (
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
        payment_method,
        payment_reference,
        metadata
    ) VALUES (
        p_user_id,
        p_type,
        p_amount,
        p_amount, -- fee yok
        v_balance_before,
        v_balance_after,
        p_reference_type,
        p_reference_id,
        'completed',
        p_description,
        p_payment_method,
        p_payment_reference,
        p_metadata
    ) RETURNING id INTO v_transaction_id;

    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC'nin authenticated kullanıcılar tarafından çalıştırılabilmesini sağla
-- (zaten varsa tekrar GRANT sorun olmaz)
GRANT EXECUTE ON FUNCTION add_to_balance(
    UUID, DECIMAL(12,2), balance_transaction_type,
    VARCHAR, UUID, TEXT, VARCHAR, VARCHAR, JSONB
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) admin_user_spending_summary view'ını güncelle:
--    total_refunds ve iade_sayisi (refund_count) ayrı sütun olarak eklenir
--    total_order_payments artık REFUND'LARI İÇERMİYOR (zaten öyleydi, net)
--    ancak yeni sütunlarla bakiye denklemi şeffaflaşır:
--      bakiye = total_topups - total_spent + total_refunds - total_withdrawn
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS admin_user_spending_summary CASCADE;

CREATE OR REPLACE VIEW admin_user_spending_summary AS
SELECT
    bt.user_id,
    p.full_name,
    p.phone,
    -- Sipariş ödemeleri (bakiyeden düşülen)
    SUM(CASE WHEN bt.type = 'order_payment' THEN bt.amount ELSE 0 END) AS total_order_payments,
    -- Yüklemeler (bakiyeye eklenen)
    SUM(CASE WHEN bt.type = 'topup' THEN bt.amount ELSE 0 END) AS total_topups,
    -- İadeler (bakiyeye eklenen, ama harcamadan düşülmüş gibi gösterilmemeli)
    SUM(CASE WHEN bt.type = 'refund' THEN bt.amount ELSE 0 END) AS total_refunds,
    -- Çekimler (bakiyeden düşülen)
    SUM(CASE WHEN bt.type = 'withdrawal' THEN bt.amount ELSE 0 END) AS total_withdrawals,
    COUNT(*) FILTER (WHERE bt.type = 'order_payment') AS order_count,
    COUNT(*) FILTER (WHERE bt.type = 'topup') AS topup_count,
    COUNT(*) FILTER (WHERE bt.type = 'refund') AS refund_count,
    MAX(bt.created_at) AS last_transaction_at
FROM balance_transactions bt
INNER JOIN profiles p ON p.id = bt.user_id
WHERE bt.status = 'completed'
GROUP BY bt.user_id, p.full_name, p.phone;

GRANT SELECT ON admin_user_spending_summary TO authenticated;
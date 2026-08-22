-- ============================================
-- ADMIN CÜZDAN YÖNETİMİ: BANKA AYARI VE AÇIKLAMA DÜZELTMESİ
-- Tarih: 2026-06-24
-- ============================================

-- balance_transactions tablosuna banka bilgileri için alanlar ekle
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'balance_transactions' AND column_name = 'bank_name') THEN
        ALTER TABLE balance_transactions ADD COLUMN bank_name VARCHAR(100);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'balance_transactions' AND column_name = 'bank_iban') THEN
        ALTER TABLE balance_transactions ADD COLUMN bank_iban VARCHAR(34);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'balance_transactions' AND column_name = 'bank_account_name') THEN
        ALTER TABLE balance_transactions ADD COLUMN bank_account_name VARCHAR(255);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'balance_transactions' AND column_name = 'admin_id') THEN
        ALTER TABLE balance_transactions ADD COLUMN admin_id UUID REFERENCES profiles(id);
    END IF;

    RAISE NOTICE 'Banka bilgisi alanları eklendi';
END $$;

-- Admin'in bakiyeli kullanıcıların tüm bakiye ve harcama geçmişini görebilmesi için VIEW oluştur
DROP VIEW IF EXISTS admin_users_with_balance CASCADE;
CREATE OR REPLACE VIEW admin_users_with_balance AS
SELECT
    ub.user_id,
    p.full_name,
    p.phone,
    p.email,
    p.username,
    ub.balance AS available_balance,
    ub.locked_balance,
    ub.total_earned,
    ub.total_spent,
    ub.total_withdrawn,
    (SELECT COUNT(*) FROM balance_transactions WHERE user_id = ub.user_id) AS total_transactions,
    (SELECT MAX(created_at) FROM balance_transactions WHERE user_id = ub.user_id) AS last_transaction_at,
    ub.created_at AS balance_created_at,
    ub.updated_at AS balance_updated_at
FROM user_balances ub
INNER JOIN profiles p ON p.id = ub.user_id
WHERE ub.balance > 0 OR ub.total_spent > 0 OR ub.total_earned > 0;

-- Kullanıcı bazlı harcama özeti view
DROP VIEW IF EXISTS admin_user_spending_summary CASCADE;
CREATE OR REPLACE VIEW admin_user_spending_summary AS
SELECT
    bt.user_id,
    p.full_name,
    p.phone,
    SUM(CASE WHEN bt.type = 'order_payment' THEN bt.amount ELSE 0 END) AS total_order_payments,
    SUM(CASE WHEN bt.type = 'topup' THEN bt.amount ELSE 0 END) AS total_topups,
    SUM(CASE WHEN bt.type = 'refund' THEN bt.amount ELSE 0 END) AS total_refunds,
    SUM(CASE WHEN bt.type = 'withdrawal' THEN bt.amount ELSE 0 END) AS total_withdrawals,
    COUNT(*) FILTER (WHERE bt.type = 'order_payment') AS order_count,
    COUNT(*) FILTER (WHERE bt.type = 'topup') AS topup_count,
    MAX(bt.created_at) AS last_transaction_at
FROM balance_transactions bt
INNER JOIN profiles p ON p.id = bt.user_id
WHERE bt.status = 'completed'
GROUP BY bt.user_id, p.full_name, p.phone;

-- Admin için tüm işlemleri kullanıcı bilgileri ile gösteren view
DROP VIEW IF EXISTS admin_balance_transactions_full CASCADE;
CREATE OR REPLACE VIEW admin_balance_transactions_full AS
SELECT
    bt.id,
    bt.user_id,
    p.full_name AS user_name,
    p.phone AS user_phone,
    p.email AS user_email,
    bt.type::text AS transaction_type,
    bt.amount,
    bt.fee,
    bt.net_amount,
    bt.balance_before,
    bt.balance_after,
    bt.reference_type,
    bt.reference_id,
    bt.status::text AS status,
    bt.description,
    bt.payment_method,
    bt.payment_reference,
    bt.bank_name,
    bt.bank_iban,
    bt.bank_account_name,
    bt.admin_id,
    admin_p.full_name AS admin_name,
    bt.created_at
FROM balance_transactions bt
INNER JOIN profiles p ON p.id = bt.user_id
LEFT JOIN profiles admin_p ON admin_p.id = bt.admin_id;

-- RLS - Admin view erişimi
GRANT SELECT ON admin_users_with_balance TO authenticated;
GRANT SELECT ON admin_user_spending_summary TO authenticated;
GRANT SELECT ON admin_balance_transactions_full TO authenticated;

-- ============================================
-- TAMAMLANDI
-- ============================================
-- ============================================================
-- PROJE_HAVIZA: 2026-07-14
-- SORUN: balance_transactions_amount_check constraint hatası
-- ÇÖZÜM: CHECK (amount > 0) -> CHECK (amount >= 0)
--
-- HATA: "new row for relation \"balance_transactions\" violates 
--        check constraint \"balance_transactions_amount_check\""
-- SEBEP: 0 TL tutarlı işlemler veya negatif tutarlar kabul edilmiyordu
-- DETAY: deduct_from_balance RPC'si amount > 0 şartı ile çalışıyor,
--        ancak checkout akışında 0 tutarlı bakiye işlemleri olabilir.
--        CHECK >= 0 yapılarak sıfır tutar kabul edilecek.
-- ============================================================

BEGIN;

-- 1) Mevcut constraint'i kaldır
ALTER TABLE public.balance_transactions 
    DROP CONSTRAINT IF EXISTS balance_transactions_amount_check;

-- 2) Yeni constraint ekle (sıfır dahil)
ALTER TABLE public.balance_transactions 
    ADD CONSTRAINT balance_transactions_amount_check 
    CHECK (amount >= 0);

-- 3) fee için de >= 0 kontrolü zaten var, teyit et
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'balance_transactions_fee_check' 
        AND table_name = 'balance_transactions'
    ) THEN
        ALTER TABLE public.balance_transactions 
            ADD CONSTRAINT balance_transactions_fee_check 
            CHECK (fee >= 0);
    END IF;
END $$;

-- 4) Şemayı yenile
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- ROLLBACK:
-- ALTER TABLE public.balance_transactions 
--     DROP CONSTRAINT IF EXISTS balance_transactions_amount_check;
-- ALTER TABLE public.balance_transactions 
--     ADD CONSTRAINT balance_transactions_amount_check 
--     CHECK (amount > 0);
-- ============================================================

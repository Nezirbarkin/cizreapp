-- ============================================
-- USER_ROLE ENUM'A KURYE ROLÜ EKLEME
-- ============================================

-- Mevcut enum'u kontrol et
DO $$
BEGIN
    -- Eğer 'courier' değeri yoksa ekle
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'courier') THEN
        ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'courier';
        RAISE NOTICE 'courier değeri user_role enum''una eklendi';
    ELSE
        RAISE NOTICE 'courier değeri zaten mevcut';
    END IF;
END $$;

-- Alternatif yöntem (PostgreSQL 14+): Eğer yukarıdaki çalışmazsa
-- DROP TYPE ile yeniden oluşturma (dikkatli kullanın, mevcut verileri etkileyebilir)
-- ALTER TYPE user_role ADD VALUE 'courier';

-- Kontrol sorgusu
SELECT enumlabel FROM pg_enum WHERE enumtypid = 'user_role'::regtype ORDER BY enumsortorder;

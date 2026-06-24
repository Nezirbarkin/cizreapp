-- payment_method enum'ına "balance" değerini ekle
-- Bu SQL'i Supabase Dashboard -> SQL Editor'den çalıştırın

-- Mevcut enum değerlerini kontrol et ve balance ekle
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid WHERE t.typname = 'payment_method' AND e.enumlabel = 'balance') THEN
        ALTER TYPE payment_method ADD VALUE 'balance';
        RAISE NOTICE 'balance değeri payment_method enum''ına eklendi';
    ELSE
        RAISE NOTICE 'balance değeri zaten mevcut';
    END IF;
END
$$;
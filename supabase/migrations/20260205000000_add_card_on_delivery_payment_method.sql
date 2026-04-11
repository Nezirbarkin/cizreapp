-- Add cardOnDelivery to payment_method enum
-- Bu migration kapıda kartla ödeme seçeneğini ekler

-- Önce mevcut enum değerlerini kontrol et
-- SELECT enum_range(NULL::payment_method);

-- cardOnDelivery değerini ekle (eğer yoksa)
DO $$
BEGIN
    -- Check if the enum type exists
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method') THEN
        -- Check if the value already exists
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = 'payment_method'::regtype 
            AND enumlabel = 'cardOnDelivery'
        ) THEN
            ALTER TYPE payment_method ADD VALUE 'cardOnDelivery';
        END IF;
    END IF;
END
$$;

-- Ayrıca card değerini de ekleyelim (kredi kartı ile online ödeme için)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_enum 
            WHERE enumtypid = 'payment_method'::regtype 
            AND enumlabel = 'card'
        ) THEN
            ALTER TYPE payment_method ADD VALUE 'card';
        END IF;
    END IF;
END
$$;

COMMENT ON TYPE payment_method IS 'Ödeme yöntemleri: cash (nakit), card (online kart), cardOnDelivery (kapıda kart)';

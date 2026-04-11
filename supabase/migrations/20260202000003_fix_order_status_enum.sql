-- =====================================================
-- FIX: Order Status Type - Eksik Değerleri Ekle
-- =====================================================
-- Mevcut order_status enum değerleri: pending, confirmed, preparing, on_the_way, delivered, cancelled
-- Eksik değerler: processing, ready

-- Type'ı güncelle - mevcut değerleri koruyarak yeni değerleri ekle
DROP TYPE IF EXISTS order_status CASCADE;

CREATE TYPE order_status AS ENUM (
    'pending',        -- Beklemede
    'processing',     -- İşleniyor (yeni eklendi)
    'ready',          -- Hazır (yeni eklendi)
    'confirmed',      -- Onaylandı
    'preparing',      -- Hazırlanıyor
    'on_the_way',     -- Yolda
    'delivered',      -- Teslim edildi
    'cancelled'       -- İptal edildi
);

-- Orders tablosunda status kolonu varsa güncelle, yoksa oluştur
DO $$
BEGIN
    -- Eğer status kolonu yoksa oluştur
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'orders'
        AND column_name = 'status'
    ) THEN
        ALTER TABLE orders ADD COLUMN status order_status DEFAULT 'pending' NOT NULL;
    ELSE
        -- Varsa varsayılan değeri güncelle
        ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'pending';
        ALTER TABLE orders ALTER COLUMN status DROP NOT NULL;
        ALTER TABLE orders ALTER COLUMN status SET NOT NULL;
    END IF;
END $$;

COMMENT ON TYPE order_status IS 'Sipariş durumları';

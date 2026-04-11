-- ORDER_ITEMS TABLOSU SCHEMA FIX

-- Önce mevcut yapıyı kontrol et
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'order_items';

-- Eğer 'price' sütunu yoksa, ekle
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'order_items' 
        AND column_name = 'price'
    ) THEN
        ALTER TABLE order_items ADD COLUMN price DECIMAL(10,2) NOT NULL DEFAULT 0;
    END IF;
END $$;

-- Eğer 'quantity' sütunu yoksa, ekle
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'order_items' 
        AND column_name = 'quantity'
    ) THEN
        ALTER TABLE order_items ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1;
    END IF;
END $$;

-- Eğer 'product_image_url' sütunu yoksa, ekle
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'order_items' 
        AND column_name = 'product_image_url'
    ) THEN
        ALTER TABLE order_items ADD COLUMN product_image_url TEXT;
    END IF;
END $$;

-- Eğer 'shop_id' sütunu yoksa, ekle
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'order_items' 
        AND column_name = 'shop_id'
    ) THEN
        ALTER TABLE order_items ADD COLUMN shop_id UUID REFERENCES shops(id);
    END IF;
END $$;

-- Eğer 'shop_name' sütunu yoksa, ekle
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'order_items' 
        AND column_name = 'shop_name'
    ) THEN
        ALTER TABLE order_items ADD COLUMN shop_name TEXT;
    END IF;
END $$;

-- Son kontrol: Tüm sütunları göster
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns 
WHERE table_name = 'order_items'
ORDER BY ordinal_position;

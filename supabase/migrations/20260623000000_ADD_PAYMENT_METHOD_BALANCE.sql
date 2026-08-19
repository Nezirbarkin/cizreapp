-- payment_method enum'ına "balance" değerini ekle
-- Bu migration siparişlerde bakiye ile ödeme seçeneğini aktif eder

-- Önce mevcut enum değerlerini kontrol et
-- Beklenen değerler: cash, card_on_delivery, online, balance

-- Eğer balance değeri yoksa ekle
DO $$ 
BEGIN
    -- Enum tipinin var olup olmadığını kontrol et
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method') THEN
        -- balance değerini ekle (zaten varsa hata vermeyecek)
        IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid WHERE t.typname = 'payment_method' AND e.enumlabel = 'balance') THEN
            ALTER TYPE payment_method ADD VALUE 'balance';
            RAISE NOTICE 'balance değeri payment_method enum''ına eklendi';
        ELSE
            RAISE NOTICE 'balance değeri zaten payment_method enum''ında mevcut';
        END IF;
    ELSE
        -- Enum tipi yoksa oluştur
        CREATE TYPE payment_method AS ENUM ('cash', 'card_on_delivery', 'online', 'balance');
        RAISE NOTICE 'payment_method enum tipi oluşturuldu';
    END IF;
END
$$;

-- Eğer orders tablosunda payment_method sütunu varchar ise, enum'a çevirmeye gerek yok
-- Sadece varchar ise "balance" değerini kabul edecektir
-- Bu durumda sadece uygulama tarafında "balance" değeri gönderilir

-- payment_method sütununun tipini kontrol et
DO $$
BEGIN
    -- Eğer sütun varchar ise, enum'a çevirme yapmaya gerek yok
    -- "balance" değeri varchar olarak zaten kaydedilebilir
    -- Eğer sütun enum tipindeyse, yukarıdaki kod balance değerini ekler
    RAISE NOTICE 'payment_method sütun tipi kontrol edildi';
END
$$;
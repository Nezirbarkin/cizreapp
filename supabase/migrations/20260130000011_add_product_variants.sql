-- Giyilebilir ürünlere beden, numara ve renk seçimi eklemek için
-- products tablosuna varyant alanları ekle

-- Ürün tipi (normal, clothing, shoes)
ALTER TABLE products 
ADD COLUMN IF NOT EXISTS product_type TEXT DEFAULT 'normal'
CHECK (product_type IN ('normal', 'clothing', 'shoes'));

-- Bedenler (giyim için) - JSONB array
ALTER TABLE products
ADD COLUMN IF NOT EXISTS sizes JSONB DEFAULT '[]'::jsonb;

-- Ayakkabı numaraları - JSONB array
ALTER TABLE products
ADD COLUMN IF NOT EXISTS shoe_sizes JSONB DEFAULT '[]'::jsonb;

-- Renkler - JSONB array of objects: [{"name": "Kırmızı", "hex": "#FF0000", "stock": 5}, ...]
ALTER TABLE products
ADD COLUMN IF NOT EXISTS colors JSONB DEFAULT '[]'::jsonb;

-- Kullanıcının seçtiği varyant (sepet için)
ALTER TABLE cart_items 
ADD COLUMN IF NOT EXISTS selected_size TEXT,
ADD COLUMN IF NOT EXISTS selected_shoe_size TEXT,
ADD COLUMN IF NOT EXISTS selected_color TEXT;

-- Varsayılan değerler için comment
COMMENT ON COLUMN products.product_type IS 'Ürün tipi: normal, clothing (giyim), shoes (ayakkabı)';
COMMENT ON COLUMN products.sizes IS 'Beden listesi (giyim için): ["S", "M", "L", "XL"]';
COMMENT ON COLUMN products.shoe_sizes IS 'Ayakkabı numara listesi: [36, 37, 38, 39, 40, 41, 42, 43, 44, 45]';
COMMENT ON COLUMN products.colors IS 'Renk listesi: [{"name": "Kırmızı", "hex": "#FF0000", "stock": 5}]';

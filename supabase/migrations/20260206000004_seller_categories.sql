-- Satıcıların kendi kategorilerini oluşturabilmesi için shops tablosuna seller_categories alanı ekle
-- Bu alan satıcının dükkanında kullanacağı özel kategorileri JSONB formatında tutar

ALTER TABLE shops 
ADD COLUMN IF NOT EXISTS seller_categories JSONB DEFAULT '[]'::jsonb;

-- Mevcut dükkanlar için boş bir dizi ata
UPDATE shops 
SET seller_categories = '[]'::jsonb 
WHERE seller_categories IS NULL;

-- Satıcı sadece kendi dükkanının kategorilerini güncelleyebilir
-- Not: Policy zaten varsa hata vermemesi için DROP ekliyoruz
DROP POLICY IF EXISTS "Sellers can update own shop categories" ON shops;

CREATE POLICY "Sellers can update own shop categories"
ON shops
FOR UPDATE
TO authenticated
USING (
  owner_id = auth.uid()
)
WITH CHECK (
  owner_id = auth.uid()
);

-- Kategorilerin düzgin JSON formatında olmasını sağlayan fonksiyon
CREATE OR REPLACE FUNCTION validate_seller_categories(categories JSONB)
RETURNS JSONB AS $$
BEGIN
  -- Kategorilerin bir dizi olduğunu kontrol et
  IF jsonb_typeof(categories) != 'array' THEN
    RAISE EXCEPTION 'Kategoriler bir dizi olmalı';
  END IF;
  
  -- Her kategorinin string olduğunu kontrol et
  FOR i IN 0..jsonb_array_length(categories)-1 LOOP
    IF jsonb_typeof(categories->i) != 'string' THEN
      RAISE EXCEPTION 'Her kategori bir metin olmalı';
    END IF;
  END LOOP;
  
  RETURN categories;
END;
$$ LANGUAGE plpgsql;

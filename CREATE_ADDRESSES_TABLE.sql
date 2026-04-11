-- Addresses tablosunu oluştur
CREATE TABLE IF NOT EXISTS addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  full_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  address_line1 TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT NOT NULL,
  district TEXT,
  postal_code TEXT,
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index'ler ekle
CREATE INDEX IF NOT EXISTS idx_addresses_user_id ON addresses(user_id);
CREATE INDEX IF NOT EXISTS idx_addresses_is_default ON addresses(user_id, is_default);

-- RLS (Row Level Security) politikalarını etkinleştir
ALTER TABLE addresses ENABLE ROW LEVEL SECURITY;

-- RLS Politikaları
-- Kullanıcılar sadece kendi adreslerini görebilir
CREATE POLICY "Users can view own addresses" 
ON addresses FOR SELECT 
USING (auth.uid() = user_id);

-- Kullanıcılar sadece kendi adreslerini ekleyebilir
CREATE POLICY "Users can insert own addresses" 
ON addresses FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Kullanıcılar sadece kendi adreslerini güncelleyebilir
CREATE POLICY "Users can update own addresses" 
ON addresses FOR UPDATE 
USING (auth.uid() = user_id);

-- Kullanıcılar sadece kendi adreslerini silebilir
CREATE POLICY "Users can delete own addresses" 
ON addresses FOR DELETE 
USING (auth.uid() = user_id);

-- updated_at otomatik güncelleme trigger'ı
CREATE OR REPLACE FUNCTION update_addresses_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER addresses_updated_at_trigger
  BEFORE UPDATE ON addresses
  FOR EACH ROW
  EXECUTE FUNCTION update_addresses_updated_at();

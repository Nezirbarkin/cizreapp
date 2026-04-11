-- Address tablosu oluştur
CREATE TABLE IF NOT EXISTS addresses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title VARCHAR(100) NOT NULL, -- Ev, İş, vb.
  full_name VARCHAR(200) NOT NULL,
  phone VARCHAR(20) NOT NULL,
  address_line1 TEXT NOT NULL,
  address_line2 TEXT,
  city VARCHAR(100) NOT NULL,
  district VARCHAR(100),
  postal_code VARCHAR(20),
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Address tablosu için RLS politikaları
ALTER TABLE addresses ENABLE ROW LEVEL SECURITY;

-- Eski policy'leri kaldır
DROP POLICY IF EXISTS "Users can view own addresses" ON addresses;
DROP POLICY IF EXISTS "Users can insert own addresses" ON addresses;
DROP POLICY IF EXISTS "Users can update own addresses" ON addresses;
DROP POLICY IF EXISTS "Users can delete own addresses" ON addresses;

-- Kullanıcı kendi adreslerini görebilir
CREATE POLICY "Users can view own addresses" ON addresses
  FOR SELECT USING (auth.uid() = user_id);

-- Kullanıcı kendi adreslerini ekleyebilir
CREATE POLICY "Users can insert own addresses" ON addresses
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Kullanıcı kendi adreslerini güncelleyebilir
CREATE POLICY "Users can update own addresses" ON addresses
  FOR UPDATE USING (auth.uid() = user_id);

-- Kullanıcı kendi adreslerini silebilir
CREATE POLICY "Users can delete own addresses" ON addresses
  FOR DELETE USING (auth.uid() = user_id);

-- Address updated_at trigger
CREATE TRIGGER update_addresses_updated_at
  BEFORE UPDATE ON addresses
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Order status enum (eğer yoksa)
DO $$ BEGIN
  CREATE TYPE order_status AS ENUM (
    'pending',      -- Beklemede
    'confirmed',    -- Onaylandı
    'preparing',    -- Hazırlanıyor
    'ready',        -- Hazır
    'on_the_way',   -- Yolda
    'delivered',    -- Teslim Edildi
    'cancelled'     -- İptal Edildi
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Payment method enum (eğer yoksa)
DO $$ BEGIN
  CREATE TYPE payment_method AS ENUM (
    'cash',           -- Kapıda Nakit
    'credit_card',    -- Kredi Kartı
    'debit_card'      -- Banka Kartı
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Orders tablosuna eksik kolonlar ekle (eğer yoksa)
DO $$ BEGIN
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS address_id UUID REFERENCES addresses(id);
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method payment_method DEFAULT 'cash';
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_status VARCHAR(50) DEFAULT 'pending';
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_notes TEXT;
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_delivery_time TIMESTAMP WITH TIME ZONE;
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP WITH TIME ZONE;
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMP WITH TIME ZONE;
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;
EXCEPTION
  WHEN others THEN NULL;
END $$;

-- Order items tablosuna eksik kolonlar ekle (eğer yoksa)
DO $$ BEGIN
  ALTER TABLE order_items ADD COLUMN IF NOT EXISTS product_name VARCHAR(255);
  ALTER TABLE order_items ADD COLUMN IF NOT EXISTS product_image_url TEXT;
  ALTER TABLE order_items ADD COLUMN IF NOT EXISTS shop_id UUID REFERENCES shops(id);
  ALTER TABLE order_items ADD COLUMN IF NOT EXISTS shop_name VARCHAR(255);
EXCEPTION
  WHEN others THEN NULL;
END $$;

-- Orders tablosu için RLS politikaları güncelle
DROP POLICY IF EXISTS "Users can view own orders" ON orders;
DROP POLICY IF EXISTS "Users can insert own orders" ON orders;
DROP POLICY IF EXISTS "Shop owners can view their shop orders" ON orders;

-- Kullanıcı kendi siparişlerini görebilir
CREATE POLICY "Users can view own orders" ON orders
  FOR SELECT USING (auth.uid() = user_id);

-- Kullanıcı sipariş oluşturabilir
CREATE POLICY "Users can insert own orders" ON orders
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Kullanıcı siparişlerini iptal edebilir (sadece pending/confirmed durumunda)
CREATE POLICY "Users can update own orders" ON orders
  FOR UPDATE USING (
    auth.uid() = user_id AND 
    status IN ('pending', 'confirmed')
  );

-- Dükkan sahipleri kendi dükkanlarının siparişlerini görebilir
CREATE POLICY "Shop owners can view their shop orders" ON orders
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = orders.shop_id AND s.owner_id = auth.uid()
    )
  );

-- Dükkan sahipleri sipariş durumunu güncelleyebilir
CREATE POLICY "Shop owners can update order status" ON orders
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = orders.shop_id AND s.owner_id = auth.uid()
    )
  );

-- Order items için RLS politikaları
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own order items" ON order_items;
DROP POLICY IF EXISTS "Users can insert own order items" ON order_items;
DROP POLICY IF EXISTS "Shop owners can view their order items" ON order_items;

-- Kullanıcı kendi sipariş öğelerini görebilir
CREATE POLICY "Users can view own order items" ON order_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_items.order_id AND o.user_id = auth.uid()
    )
  );

-- Kullanıcı sipariş öğesi ekleyebilir
CREATE POLICY "Users can insert own order items" ON order_items
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_items.order_id AND o.user_id = auth.uid()
    )
  );

-- Dükkan sahipleri kendi dükkanlarının sipariş öğelerini görebilir
CREATE POLICY "Shop owners can view their order items" ON order_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = order_items.shop_id AND s.owner_id = auth.uid()
    )
  );

-- Index'ler
CREATE INDEX IF NOT EXISTS idx_addresses_user_id ON addresses(user_id);
CREATE INDEX IF NOT EXISTS idx_addresses_is_default ON addresses(user_id, is_default);
CREATE INDEX IF NOT EXISTS idx_orders_address_id ON orders(address_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_items_shop_id ON order_items(shop_id);

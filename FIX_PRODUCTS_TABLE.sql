-- ====================================
-- PRODUCTS TABLOSU TAM DÜZELTME
-- Tüm eksik sütunları ekle
-- ====================================

-- Adım 1: Products tablosuna eksik sütunları ekle
ALTER TABLE products
ADD COLUMN IF NOT EXISTS category VARCHAR(100),
ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS stock_quantity INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS old_price DECIMAL(10, 2),
ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Adım 2: Constraint'leri ekle (sadece yoksa)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'positive_stock' 
        AND conrelid = 'products'::regclass
    ) THEN
        ALTER TABLE products 
        ADD CONSTRAINT positive_stock CHECK (stock_quantity >= 0);
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'positive_price' 
        AND conrelid = 'products'::regclass
    ) THEN
        ALTER TABLE products 
        ADD CONSTRAINT positive_price CHECK (price >= 0);
    END IF;
END $$;

-- Adım 3: Index'leri ekle
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_is_available ON products(is_available);

-- Adım 4: Cart tablosu
CREATE TABLE IF NOT EXISTS cart (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT cart_positive_quantity CHECK (quantity > 0),
  CONSTRAINT cart_unique_user_product UNIQUE(user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_cart_user_id ON cart(user_id);
CREATE INDEX IF NOT EXISTS idx_cart_product_id ON cart(product_id);

-- Adım 5: Coupons tablosu
CREATE TABLE IF NOT EXISTS coupons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(50) NOT NULL UNIQUE,
  discount_type VARCHAR(20) NOT NULL,
  discount_value DECIMAL(10, 2) NOT NULL,
  min_order_amount DECIMAL(10, 2) DEFAULT 0,
  max_discount_amount DECIMAL(10, 2),
  usage_limit INTEGER,
  usage_count INTEGER DEFAULT 0,
  valid_from TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  valid_until TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT coupons_valid_discount_type CHECK (discount_type IN ('percentage', 'fixed')),
  CONSTRAINT coupons_positive_discount CHECK (discount_value > 0),
  CONSTRAINT coupons_valid_usage_limit CHECK (usage_limit IS NULL OR usage_limit > 0)
);

CREATE INDEX IF NOT EXISTS idx_coupons_code ON coupons(code);
CREATE INDEX IF NOT EXISTS idx_coupons_is_active ON coupons(is_active);

-- Adım 6: Orders tablosu
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  order_number VARCHAR(50) NOT NULL UNIQUE,
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  
  subtotal DECIMAL(10, 2) NOT NULL,
  delivery_fee DECIMAL(10, 2) DEFAULT 0,
  discount_amount DECIMAL(10, 2) DEFAULT 0,
  total_amount DECIMAL(10, 2) NOT NULL,
  
  coupon_id UUID REFERENCES coupons(id),
  coupon_code VARCHAR(50),
  
  delivery_address TEXT NOT NULL,
  delivery_latitude DECIMAL(10, 8),
  delivery_longitude DECIMAL(11, 8),
  
  payment_method VARCHAR(50),
  payment_status VARCHAR(50) DEFAULT 'pending',
  
  customer_notes TEXT,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  delivered_at TIMESTAMP WITH TIME ZONE,
  
  CONSTRAINT orders_valid_status CHECK (status IN ('pending', 'confirmed', 'preparing', 'ready', 'on_delivery', 'delivered', 'cancelled')),
  CONSTRAINT orders_valid_payment_status CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')),
  CONSTRAINT orders_positive_amounts CHECK (subtotal >= 0 AND total_amount >= 0)
);

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_shop_id ON orders(shop_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

-- Adım 7: Order items tablosu
CREATE TABLE IF NOT EXISTS order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  product_name VARCHAR(255) NOT NULL,
  product_price DECIMAL(10, 2) NOT NULL,
  quantity INTEGER NOT NULL,
  subtotal DECIMAL(10, 2) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT order_items_positive_quantity CHECK (quantity > 0),
  CONSTRAINT order_items_positive_price CHECK (product_price >= 0)
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);

-- ====================================
-- TRIGGERS
-- ====================================

CREATE OR REPLACE FUNCTION update_cart_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS cart_updated_at_trigger ON cart;
CREATE TRIGGER cart_updated_at_trigger
  BEFORE UPDATE ON cart
  FOR EACH ROW
  EXECUTE FUNCTION update_cart_updated_at();

CREATE OR REPLACE FUNCTION update_orders_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS orders_updated_at_trigger ON orders;
CREATE TRIGGER orders_updated_at_trigger
  BEFORE UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION update_orders_updated_at();

-- ====================================
-- RLS POLİCİLERİ
-- ====================================

ALTER TABLE cart ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- Cart RLS
DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerini görebilir" ON cart;
CREATE POLICY "Kullanıcılar kendi sepetlerini görebilir"
  ON cart FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerine ekleyebilir" ON cart;
CREATE POLICY "Kullanıcılar kendi sepetlerine ekleyebilir"
  ON cart FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerini güncelleyebilir" ON cart;
CREATE POLICY "Kullanıcılar kendi sepetlerini güncelleyebilir"
  ON cart FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Kullanıcılar kendi sepetlerinden silebilir" ON cart;
CREATE POLICY "Kullanıcılar kendi sepetlerinden silebilir"
  ON cart FOR DELETE
  USING (auth.uid() = user_id);

-- Coupons RLS
DROP POLICY IF EXISTS "Herkes aktif kuponları görebilir" ON coupons;
CREATE POLICY "Herkes aktif kuponları görebilir"
  ON coupons FOR SELECT
  USING (is_active = true);

-- Orders RLS
DROP POLICY IF EXISTS "Kullanıcılar kendi siparişlerini görebilir" ON orders;
CREATE POLICY "Kullanıcılar kendi siparişlerini görebilir"
  ON orders FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Dükkan sahipleri kendi siparişlerini görebilir" ON orders;
CREATE POLICY "Dükkan sahipleri kendi siparişlerini görebilir"
  ON orders FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM shops
      WHERE shops.id = shop_id
      AND shops.owner_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Kullanıcılar sipariş oluşturabilir" ON orders;
CREATE POLICY "Kullanıcılar sipariş oluşturabilir"
  ON orders FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Kullanıcılar kendi siparişlerini güncelleyebilir" ON orders;
CREATE POLICY "Kullanıcılar kendi siparişlerini güncelleyebilir"
  ON orders FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Dükkan sahipleri kendi siparişlerini güncelleyebilir" ON orders;
CREATE POLICY "Dükkan sahipleri kendi siparişlerini güncelleyebilir"
  ON orders FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM shops
      WHERE shops.id = shop_id
      AND shops.owner_id = auth.uid()
    )
  );

-- Order Items RLS
DROP POLICY IF EXISTS "Sipariş sahibi order items görebilir" ON order_items;
CREATE POLICY "Sipariş sahibi order items görebilir"
  ON order_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM orders
      WHERE orders.id = order_id
      AND orders.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Dükkan sahibi order items görebilir" ON order_items;
CREATE POLICY "Dükkan sahibi order items görebilir"
  ON order_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM orders
      JOIN shops ON shops.id = orders.shop_id
      WHERE orders.id = order_id
      AND shops.owner_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Sipariş oluştururken items eklenebilir" ON order_items;
CREATE POLICY "Sipariş oluştururken items eklenebilir"
  ON order_items FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders
      WHERE orders.id = order_id
      AND orders.user_id = auth.uid()
    )
  );

-- ====================================
-- COUPONS TABLOSUNA EKSIK SÜTUNLAR EKLE
-- ====================================

-- Coupons tablosu zaten var, eksik sütunları ekle
ALTER TABLE coupons
ADD COLUMN IF NOT EXISTS max_discount_amount DECIMAL(10, 2),
ADD COLUMN IF NOT EXISTS usage_limit INTEGER,
ADD COLUMN IF NOT EXISTS usage_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- ====================================
-- BAŞARILI!
-- ====================================
SELECT 'Tüm tablolar ve sütunlar başarıyla oluşturuldu!' as result;

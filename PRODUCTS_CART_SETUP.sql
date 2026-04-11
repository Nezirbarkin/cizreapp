-- ====================================
-- PRODUCTS, CART, ORDERS VE COUPONS TABLOLARI
-- CizreApp - E-Ticaret Sistemi
-- ====================================

-- 1. PRODUCTS TABLOSU (Ürünler)
CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  price DECIMAL(10, 2) NOT NULL,
  old_price DECIMAL(10, 2), -- İndirim öncesi fiyat
  stock_quantity INTEGER DEFAULT 0,
  image_url TEXT,
  category VARCHAR(100),
  is_available BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT positive_price CHECK (price >= 0),
  CONSTRAINT positive_stock CHECK (stock_quantity >= 0)
);

-- 2. CART TABLOSU (Sepet)
CREATE TABLE IF NOT EXISTS cart (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT positive_quantity CHECK (quantity > 0),
  CONSTRAINT unique_user_product UNIQUE(user_id, product_id)
);

-- 3. COUPONS TABLOSU (Kuponlar)
CREATE TABLE IF NOT EXISTS coupons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(50) NOT NULL UNIQUE,
  discount_type VARCHAR(20) NOT NULL, -- 'percentage' veya 'fixed'
  discount_value DECIMAL(10, 2) NOT NULL,
  min_order_amount DECIMAL(10, 2) DEFAULT 0,
  max_discount_amount DECIMAL(10, 2), -- Maksimum indirim limiti (yüzdelik için)
  usage_limit INTEGER, -- Toplam kullanım limiti
  usage_count INTEGER DEFAULT 0,
  valid_from TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  valid_until TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT valid_discount_type CHECK (discount_type IN ('percentage', 'fixed')),
  CONSTRAINT positive_discount CHECK (discount_value > 0),
  CONSTRAINT valid_usage_limit CHECK (usage_limit IS NULL OR usage_limit > 0)
);

-- 4. ORDERS TABLOSU (Siparişler)
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  order_number VARCHAR(50) NOT NULL UNIQUE,
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  
  -- Fiyat bilgileri
  subtotal DECIMAL(10, 2) NOT NULL,
  delivery_fee DECIMAL(10, 2) DEFAULT 0,
  discount_amount DECIMAL(10, 2) DEFAULT 0,
  total_amount DECIMAL(10, 2) NOT NULL,
  
  -- Kupon bilgisi
  coupon_id UUID REFERENCES coupons(id),
  coupon_code VARCHAR(50),
  
  -- Teslimat bilgileri
  delivery_address TEXT NOT NULL,
  delivery_latitude DECIMAL(10, 8),
  delivery_longitude DECIMAL(11, 8),
  
  -- Ödeme bilgileri
  payment_method VARCHAR(50), -- 'cash', 'credit_card', 'online'
  payment_status VARCHAR(50) DEFAULT 'pending',
  
  -- Notlar
  customer_notes TEXT,
  
  -- Tarihler
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  delivered_at TIMESTAMP WITH TIME ZONE,
  
  CONSTRAINT valid_status CHECK (status IN ('pending', 'confirmed', 'preparing', 'ready', 'on_delivery', 'delivered', 'cancelled')),
  CONSTRAINT valid_payment_status CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')),
  CONSTRAINT positive_amounts CHECK (subtotal >= 0 AND total_amount >= 0)
);

-- 5. ORDER_ITEMS TABLOSU (Sipariş Kalemleri)
CREATE TABLE IF NOT EXISTS order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  product_name VARCHAR(255) NOT NULL, -- Ürün silinirse diye ismi saklıyoruz
  product_price DECIMAL(10, 2) NOT NULL,
  quantity INTEGER NOT NULL,
  subtotal DECIMAL(10, 2) NOT NULL, -- price * quantity
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT positive_quantity CHECK (quantity > 0),
  CONSTRAINT positive_price CHECK (product_price >= 0)
);

-- ====================================
-- İNDEXLER (Performans için)
-- ====================================

CREATE INDEX IF NOT EXISTS idx_products_shop_id ON products(shop_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_is_available ON products(is_available);

CREATE INDEX IF NOT EXISTS idx_cart_user_id ON cart(user_id);
CREATE INDEX IF NOT EXISTS idx_cart_product_id ON cart(product_id);

CREATE INDEX IF NOT EXISTS idx_coupons_code ON coupons(code);
CREATE INDEX IF NOT EXISTS idx_coupons_is_active ON coupons(is_active);

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_shop_id ON orders(shop_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);

-- ====================================
-- TRİGGERS (Otomatik güncelleme)
-- ====================================

-- Products updated_at trigger
CREATE OR REPLACE FUNCTION update_products_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER products_updated_at_trigger
  BEFORE UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION update_products_updated_at();

-- Cart updated_at trigger
CREATE OR REPLACE FUNCTION update_cart_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER cart_updated_at_trigger
  BEFORE UPDATE ON cart
  FOR EACH ROW
  EXECUTE FUNCTION update_cart_updated_at();

-- Orders updated_at trigger
CREATE OR REPLACE FUNCTION update_orders_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_updated_at_trigger
  BEFORE UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION update_orders_updated_at();

-- Order number otomatik oluşturma
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS TRIGGER AS $$
BEGIN
  NEW.order_number = 'ORD-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(NEXTVAL('order_number_seq')::TEXT, 6, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Sequence oluştur
CREATE SEQUENCE IF NOT EXISTS order_number_seq START 1;

CREATE TRIGGER generate_order_number_trigger
  BEFORE INSERT ON orders
  FOR EACH ROW
  WHEN (NEW.order_number IS NULL)
  EXECUTE FUNCTION generate_order_number();

-- ====================================
-- ROW LEVEL SECURITY (RLS) POLİCİLERİ
-- ====================================

-- Products RLS
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Herkes ürünleri görebilir
CREATE POLICY "Herkes ürünleri görüntüleyebilir"
  ON products FOR SELECT
  USING (true);

-- Sadece dükkan sahipleri kendi ürünlerini ekleyebilir/düzenleyebilir
CREATE POLICY "Dükkan sahipleri ürün ekleyebilir"
  ON products FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM shops
      WHERE shops.id = shop_id
      AND shops.owner_id = auth.uid()
    )
  );

CREATE POLICY "Dükkan sahipleri kendi ürünlerini güncelleyebilir"
  ON products FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM shops
      WHERE shops.id = shop_id
      AND shops.owner_id = auth.uid()
    )
  );

CREATE POLICY "Dükkan sahipleri kendi ürünlerini silebilir"
  ON products FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM shops
      WHERE shops.id = shop_id
      AND shops.owner_id = auth.uid()
    )
  );

-- Cart RLS
ALTER TABLE cart ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Kullanıcılar kendi sepetlerini görebilir"
  ON cart FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Kullanıcılar kendi sepetlerine ekleyebilir"
  ON cart FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Kullanıcılar kendi sepetlerini güncelleyebilir"
  ON cart FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Kullanıcılar kendi sepetlerinden silebilir"
  ON cart FOR DELETE
  USING (auth.uid() = user_id);

-- Coupons RLS
ALTER TABLE coupons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Herkes aktif kuponları görebilir"
  ON coupons FOR SELECT
  USING (is_active = true);

-- Orders RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Kullanıcılar kendi siparişlerini görebilir"
  ON orders FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Dükkan sahipleri kendi siparişlerini görebilir"
  ON orders FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM shops
      WHERE shops.id = shop_id
      AND shops.owner_id = auth.uid()
    )
  );

CREATE POLICY "Kullanıcılar sipariş oluşturabilir"
  ON orders FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Kullanıcılar kendi siparişlerini güncelleyebilir"
  ON orders FOR UPDATE
  USING (auth.uid() = user_id);

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
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Sipariş sahibi order items görebilir"
  ON order_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM orders
      WHERE orders.id = order_id
      AND orders.user_id = auth.uid()
    )
  );

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
-- ÖRNEK VERİLER
-- ====================================

-- Örnek ürünler ekleyelim (shop_id'leri mevcut shops tablosundan alınmalı)
-- NOT: Bu kısım opsiyonel, gerçek ürünler dükkan sahipleri tarafından eklenecek

-- Örnek kupon
INSERT INTO coupons (code, discount_type, discount_value, min_order_amount, max_discount_amount, usage_limit, valid_until, is_active)
VALUES 
  ('WELCOME10', 'percentage', 10.00, 50.00, 20.00, 100, NOW() + INTERVAL '30 days', true),
  ('SAVE20', 'fixed', 20.00, 100.00, NULL, 50, NOW() + INTERVAL '30 days', true),
  ('FREESHIP', 'percentage', 100.00, 0.00, 15.00, 200, NOW() + INTERVAL '60 days', true)
ON CONFLICT (code) DO NOTHING;

-- ====================================
-- TAMAMLANDI
-- ====================================
-- Artık products, cart, orders, coupons tabloları hazır!
-- Flutter tarafında model ve service'ler oluşturulabilir.

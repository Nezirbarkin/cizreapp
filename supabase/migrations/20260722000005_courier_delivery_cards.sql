-- Teslimat kartları (harita seçeneği)
CREATE TABLE IF NOT EXISTS delivery_card_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  fee NUMERIC(10,2) DEFAULT 0,
  delivery_time_min INTEGER DEFAULT 30,
  delivery_time_max INTEGER DEFAULT 60,
  free_min_order NUMERIC(10,2),
  is_active BOOLEAN DEFAULT true,
  display_order INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- İndeks
CREATE INDEX idx_delivery_card_is_active ON delivery_card_options(is_active);

-- RLS: Herkese görünebilir
ALTER TABLE delivery_card_options ENABLE ROW LEVEL SECURITY;
CREATE POLICY "delivery_card_public_read" ON delivery_card_options
  FOR SELECT TO authenticated, anon USING (is_active = true);

CREATE POLICY "delivery_card_admin_write" ON delivery_card_options
  FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Kurye servisi ayarları
CREATE TABLE IF NOT EXISTS courier_service_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  enabled BOOLEAN DEFAULT false,
  allows_user_requests BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Default ayarlar oluştur
INSERT INTO courier_service_settings (enabled, allows_user_requests)
VALUES (false, false)
ON CONFLICT DO NOTHING;

-- Varsayılan kartları ekle
INSERT INTO delivery_card_options (name, description, fee, delivery_time_min, delivery_time_max, free_min_order, display_order)
VALUES
  ('Standart Teslimat', '2-4 saat içinde teslimat', 15.00, 120, 240, NULL, 1),
  ('Express Teslimat', '30 dakika içinde teslimat', 0.00, 30, 60, 50.00, 2),
  ('Same Day', '6-8 saat içinde teslimat', 25.00, 360, 480, NULL, 3)
ON CONFLICT DO NOTHING;

-- Kullanıcı kargo talepleri tablosu
CREATE TABLE IF NOT EXISTS courier_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  recipient_name VARCHAR(255) NOT NULL,
  recipient_phone VARCHAR(20) NOT NULL,
  delivery_address TEXT NOT NULL,
  description TEXT,
  delivery_card_id UUID REFERENCES delivery_card_options(id),
  delivery_fee NUMERIC(10,2) DEFAULT 0,
  status VARCHAR(50) DEFAULT 'pending',
  courier_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- İndeksler
CREATE INDEX idx_courier_requests_sender_id ON courier_requests(sender_id);
CREATE INDEX idx_courier_requests_status ON courier_requests(status);
CREATE INDEX idx_courier_requests_courier_id ON courier_requests(courier_id);

-- RLS: Basit policy (daha sonra geliştir)
ALTER TABLE courier_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "courier_requests_authenticated" ON courier_requests
  FOR ALL TO authenticated USING (true);

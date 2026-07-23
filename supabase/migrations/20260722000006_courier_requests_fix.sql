-- Önceki hatalı migration'ı temizle ve yeniden oluştur
DROP TABLE IF EXISTS courier_requests CASCADE;

-- Kullanıcı kargo talepleri tablosu
CREATE TABLE courier_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_name VARCHAR(255) NOT NULL,
  recipient_phone VARCHAR(20) NOT NULL,
  delivery_address TEXT NOT NULL,
  description TEXT,
  delivery_card_id UUID REFERENCES delivery_card_options(id) ON DELETE SET NULL,
  delivery_fee NUMERIC(10,2) DEFAULT 0,
  status VARCHAR(50) DEFAULT 'pending',
  courier_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- İndeksler
CREATE INDEX idx_courier_requests_sender_id ON courier_requests(sender_id);
CREATE INDEX idx_courier_requests_status ON courier_requests(status);
CREATE INDEX idx_courier_requests_courier_id ON courier_requests(courier_id);

-- RLS: Basit (production'da geliştir)
ALTER TABLE courier_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "courier_requests_authenticated" ON courier_requests
  FOR ALL TO authenticated USING (true);

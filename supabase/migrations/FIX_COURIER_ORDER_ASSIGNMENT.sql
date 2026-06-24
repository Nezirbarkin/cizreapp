-- ============================================
-- FIX: Kurye Sipariş Atama ve Bildirim Sistemi
-- ============================================

-- 1. orders tablosuna delivered_courier_* alanları ekle (yoksa)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_courier_id UUID;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_courier_name TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_courier_phone TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;

-- 2. courier_assignments için index ekle
CREATE INDEX IF NOT EXISTS idx_courier_assignments_order_id ON courier_assignments(order_id);
CREATE INDEX IF NOT EXISTS idx_courier_assignments_courier_id ON courier_assignments(courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_assignments_status ON courier_assignments(status);

-- 3. orders tablosunda foreign key ve index
CREATE INDEX IF NOT EXISTS idx_orders_shop_id ON orders(shop_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

COMMENT ON COLUMN orders.delivered_courier_id IS 'Siparişi teslim eden kurye ID';
COMMENT ON COLUMN orders.delivered_courier_name IS 'Siparişi teslim eden kurye adı';
COMMENT ON COLUMN orders.delivered_courier_phone IS 'Siparişi teslim eden kurye telefonu';
COMMENT ON COLUMN orders.delivered_at IS 'Teslim tarihi';

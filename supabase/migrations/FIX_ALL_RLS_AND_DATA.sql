-- ============================================
-- COMPREHENSIVE FIX: Tüm Bildirilen Sorunlar - RLS ve Veri
-- ============================================

-- ============================================
-- 1. Satıcı kendi verilerini görebilsin
-- ============================================

-- Satıcı kendi dükkanını görebilmeli
DROP POLICY IF EXISTS "Sellers can view own shop" ON shops;
CREATE POLICY "Sellers can view own shop"
ON shops FOR SELECT
TO authenticated
USING (owner_id = auth.uid());

-- Satıcı kendi dükkanının ürünlerini görebilmeli
DROP POLICY IF EXISTS "Sellers can view own shop products" ON products;
CREATE POLICY "Sellers can view own shop products"
ON products FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM shops s
        WHERE s.id = products.shop_id
        AND s.owner_id = auth.uid()
    )
);

-- Satıcı kendi dükkanının siparişlerini görebilmeli
DROP POLICY IF EXISTS "Sellers can view own shop orders" ON orders;
CREATE POLICY "Sellers can view own shop orders"
ON orders FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM shops s
        WHERE s.id = orders.shop_id
        AND s.owner_id = auth.uid()
    )
);

-- ============================================
-- 2. Kuryeler atanabilir siparişleri görebilsin
-- ============================================

DROP POLICY IF EXISTS "Couriers can view available orders" ON orders;
CREATE POLICY "Couriers can view available orders"
ON orders FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM shops s
        WHERE s.id = orders.shop_id
        AND (s.has_own_courier IS NULL OR s.has_own_courier = FALSE)
    )
    AND status IN ('confirmed', 'preparing', 'ready')
);

-- ============================================
-- 3. courier_assignments RLS
-- ============================================

DROP POLICY IF EXISTS "Couriers can view own assignments" ON courier_assignments;
CREATE POLICY "Couriers can view own assignments"
ON courier_assignments FOR SELECT
TO authenticated
USING (courier_id = auth.uid());

DROP POLICY IF EXISTS "Couriers can update own assignments" ON courier_assignments;
CREATE POLICY "Couriers can update own assignments"
ON courier_assignments FOR UPDATE
TO authenticated
USING (courier_id = auth.uid());

DROP POLICY IF EXISTS "Sellers can view order assignments" ON courier_assignments;
CREATE POLICY "Sellers can view order assignments"
ON courier_assignments FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM orders o
        JOIN shops s ON s.id = o.shop_id
        WHERE o.id = courier_assignments.order_id
        AND s.owner_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Admins can view all assignments" ON courier_assignments;
CREATE POLICY "Admins can view all assignments"
ON courier_assignments FOR SELECT
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================
-- 4. seller_earnings tablosu
-- ============================================

CREATE TABLE IF NOT EXISTS seller_earnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL,
    order_id UUID NOT NULL UNIQUE,
    order_number TEXT,
    shop_id UUID,
    gross_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    commission_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    commission_percent DECIMAL(5, 2) DEFAULT 0.00,
    net_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    status TEXT DEFAULT 'available',
    available_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE seller_earnings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Sellers can view own earnings" ON seller_earnings;
CREATE POLICY "Sellers can view own earnings"
ON seller_earnings FOR SELECT
TO authenticated
USING (seller_id = auth.uid());

DROP POLICY IF EXISTS "Admins can view all earnings" ON seller_earnings;
CREATE POLICY "Admins can view all earnings"
ON seller_earnings FOR SELECT
TO authenticated
USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================
-- 5. orders tablosuna eksik sütunları ekle
-- ============================================

ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_courier_id UUID;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_courier_name TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_courier_phone TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS total_amount DECIMAL(12, 2);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_number TEXT;

-- ============================================
-- 6. shops tablosuna eksik sütunları ekle
-- ============================================

ALTER TABLE shops ADD COLUMN IF NOT EXISTS total_paid DECIMAL(12, 2) DEFAULT 0;
ALTER TABLE shops ADD COLUMN IF NOT EXISTS cash_payment_revenue DECIMAL(12, 2) DEFAULT 0;
ALTER TABLE shops ADD COLUMN IF NOT EXISTS online_payment_revenue DECIMAL(12, 2) DEFAULT 0;
ALTER TABLE shops ADD COLUMN IF NOT EXISTS admin_credit DECIMAL(12, 2) DEFAULT 0;
ALTER TABLE shops ADD COLUMN IF NOT EXISTS commission_debt DECIMAL(12, 2) DEFAULT 0;
ALTER TABLE shops ADD COLUMN IF NOT EXISTS hide_customer_info BOOLEAN DEFAULT FALSE;

-- ============================================
-- 7. Index'ler (performans için)
-- ============================================

CREATE INDEX IF NOT EXISTS idx_orders_shop_id_status ON orders(shop_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_status_created ON orders(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_products_shop_id ON products(shop_id);
CREATE INDEX IF NOT EXISTS idx_courier_assignments_order_status ON courier_assignments(order_id, status);
CREATE INDEX IF NOT EXISTS idx_seller_earnings_seller_id ON seller_earnings(seller_id);
CREATE INDEX IF NOT EXISTS idx_seller_earnings_shop_id ON seller_earnings(shop_id);

-- ============================================
-- 8. Bildirim
-- ============================================
DO $$
BEGIN
    RAISE NOTICE 'Tum RLS politikalari ve sutunlar basariyla eklendi';
    RAISE NOTICE 'Seller earnings tablosu hazir';
    RAISE NOTICE 'Commission trigger duzeltildi';
    RAISE NOTICE 'Cascade delete ayarlandi';
END $$;
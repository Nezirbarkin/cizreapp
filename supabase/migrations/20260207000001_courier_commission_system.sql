-- Kuryesi olan/olmayan satıcılar için komisyon sistemi
-- Detaylı açıklama ve örneklerle

/*
KURYESI OLAN SATICILAR:
- Kapıda ödeme: Satıcı parayı alır, komisyon borcu oluşur (ödeme isteği oluşturamaz)
- Online ödeme: Admin parayı alır, satıcı alacaklı olur (komisyon borcu düşülür)

KURYESI OLMAYAN SATICILAR:
- Her durumda: Admin tüm parayı alır, teslimat + komisyon kesilir
*/

-- 1. Orders tablosuna yeni alanlar ekle
ALTER TABLE orders ADD COLUMN IF NOT EXISTS seller_has_own_courier BOOLEAN DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS seller_debt_amount NUMERIC(10,2) DEFAULT 0; -- Satıcının komisyon borcu
ALTER TABLE orders ADD COLUMN IF NOT EXISTS seller_credit_amount NUMERIC(10,2) DEFAULT 0; -- Satıcının alacağı

-- 2. Payout requests tablosuna detay alanları ekle
ALTER TABLE payout_requests ADD COLUMN IF NOT EXISTS total_sales NUMERIC(10,2) DEFAULT 0; -- Toplam satış
ALTER TABLE payout_requests ADD COLUMN IF NOT EXISTS commission_debt NUMERIC(10,2) DEFAULT 0; -- Komisyon borcu
ALTER TABLE payout_requests ADD COLUMN IF NOT EXISTS delivery_fee_total NUMERIC(10,2) DEFAULT 0; -- Teslimat ücreti toplamı
ALTER TABLE payout_requests ADD COLUMN IF NOT EXISTS net_receivable NUMERIC(10,2) DEFAULT 0; -- Net alacak
ALTER TABLE payout_requests ADD COLUMN IF NOT EXISTS payment_details JSONB DEFAULT '{}'; -- Detaylı açıklama

-- 3. Shops tablosuna borç/alacak takibi ekle
ALTER TABLE shops ADD COLUMN IF NOT EXISTS commission_debt NUMERIC(10,2) DEFAULT 0; -- Toplam komisyon borcu (kapıda ödeme)
ALTER TABLE shops ADD COLUMN IF NOT EXISTS admin_credit NUMERIC(10,2) DEFAULT 0; -- Adminden alacak (online ödeme)

-- 4. Komisyon hesaplama trigger - YENİ MANTIK
DROP TRIGGER IF EXISTS calculate_order_commission ON orders CASCADE;
CREATE OR REPLACE FUNCTION calculate_order_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_commission_rate NUMERIC;
  v_has_own_courier BOOLEAN;
  v_admin_commission NUMERIC;
  v_delivery_fee NUMERIC;
BEGIN
  -- Satıcının bilgilerini al
  SELECT commission_rate, has_own_courier
  INTO v_commission_rate, v_has_own_courier
  FROM shops
  WHERE id = NEW.shop_id;

  -- Varsayılan değerler
  v_commission_rate := COALESCE(v_commission_rate, 0.20); -- %20
  v_has_own_courier := COALESCE(v_has_own_courier, FALSE);
  v_delivery_fee := NEW.delivery_fee;

  -- Komisyonu hesapla (subtotal üzerinden)
  v_admin_commission := NEW.subtotal * v_commission_rate;

  -- Kuryesi durumunu kaydet
  NEW.seller_has_own_courier := v_has_own_courier;
  NEW.admin_commission := v_admin_commission;

  -- KURYESI OLAN SATICI
  IF v_has_own_courier THEN
    IF NEW.payment_method IN ('cash', 'card_on_delivery') THEN
      -- KAPIDA ÖDEME: Satıcı parayı aldı, komisyon BORCU oluştur
      NEW.admin_delivery_fee := 0; -- Teslimat ücreti kesilmez
      NEW.seller_debt_amount := v_admin_commission; -- Komisyon borcu
      NEW.seller_credit_amount := 0;
      NEW.seller_net_amount := NEW.total - v_admin_commission; -- Satıcıda kalan (fiili)
      NEW.commission_status := 'debt'; -- Borç durumu
    ELSE
      -- ONLINE ÖDEME: Admin parayı aldı, satıcı ALACAKLI
      NEW.admin_delivery_fee := 0; -- Teslimat ücreti yine kesilmez
      NEW.seller_debt_amount := 0;
      NEW.seller_credit_amount := NEW.total - v_admin_commission; -- Teslimat + net kazanç
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'credit'; -- Alacak durumu
    END IF;
  
  -- KURYESI OLMAYAN SATICI
  ELSE
    -- HER DURUMDA: Admin tüm parayı alır
    NEW.admin_delivery_fee := v_delivery_fee; -- Teslimat ücreti admin'e
    NEW.seller_debt_amount := 0;
    NEW.seller_credit_amount := NEW.subtotal - v_admin_commission; -- Sadece ürün net kazancı
    NEW.seller_net_amount := NEW.subtotal - v_admin_commission;
    NEW.commission_status := 'credit'; -- Alacak (teslimat hariç)
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_order_commission
BEFORE INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION calculate_order_commission();

-- 5. Shop'un borç/alacak durumunu güncelle
DROP TRIGGER IF EXISTS update_shop_balance ON orders CASCADE;
CREATE OR REPLACE FUNCTION update_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Satıcının borç/alacak durumunu güncelle
  UPDATE shops
  SET 
    commission_debt = commission_debt + NEW.seller_debt_amount,
    admin_credit = admin_credit + NEW.seller_credit_amount,
    updated_at = NOW()
  WHERE id = NEW.shop_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_shop_balance
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION update_shop_balance();

-- 6. Ödeme isteği oluştururken borç/alacak kontrolü
DROP TRIGGER IF EXISTS validate_payout_request ON payout_requests CASCADE;
CREATE OR REPLACE FUNCTION validate_payout_request()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_credit NUMERIC;
  v_commission_debt NUMERIC;
  v_net_receivable NUMERIC;
  v_has_own_courier BOOLEAN;
BEGIN
  -- Satıcının durumunu al
  SELECT admin_credit, commission_debt, has_own_courier
  INTO v_admin_credit, v_commission_debt, v_has_own_courier
  FROM shops
  WHERE id = NEW.shop_id;

  -- Kuryesi olmayan satıcılar direkt alacağını alır
  IF NOT v_has_own_courier THEN
    NEW.net_receivable := v_admin_credit;
    NEW.commission_debt := 0;
    NEW.amount := v_admin_credit;
  -- Kuryesi olan satıcılar: Alacak - Borç
  ELSE
    v_net_receivable := v_admin_credit - v_commission_debt;
    
    IF v_net_receivable <= 0 THEN
      RAISE EXCEPTION 'Ödeme isteği oluşturulamaz. Komisyon borcunuz: ₺%. Online ödeme alacağınız: ₺%', 
        v_commission_debt, v_admin_credit;
    END IF;

    NEW.net_receivable := v_net_receivable;
    NEW.commission_debt := v_commission_debt;
    NEW.admin_credit := v_admin_credit;
    NEW.amount := v_net_receivable;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_payout_request
BEFORE INSERT ON payout_requests
FOR EACH ROW
EXECUTE FUNCTION validate_payout_request();

-- 7. Ödeme isteği onaylandığında shop balance'ı sıfırla
DROP TRIGGER IF EXISTS clear_shop_balance ON payout_requests CASCADE;
CREATE OR REPLACE FUNCTION clear_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status != 'approved' THEN
    UPDATE shops
    SET 
      commission_debt = 0,
      admin_credit = 0,
      updated_at = NOW()
    WHERE id = NEW.shop_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER clear_shop_balance
AFTER UPDATE ON payout_requests
FOR EACH ROW
EXECUTE FUNCTION clear_shop_balance();

-- 8. commission_status enum güncelle
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'commission_status_type') THEN
        CREATE TYPE commission_status_type AS ENUM ('pending', 'paid', 'debt', 'credit');
    END IF;
END $$;

ALTER TABLE orders ALTER COLUMN commission_status TYPE VARCHAR(20);

-- 9. İndeksler (performans)
CREATE INDEX IF NOT EXISTS idx_orders_seller_courier ON orders(seller_has_own_courier);
CREATE INDEX IF NOT EXISTS idx_orders_commission_status ON orders(commission_status);
CREATE INDEX IF NOT EXISTS idx_shops_balance ON shops(commission_debt, admin_credit);

-- 10. Mevcut siparişleri güncelle (geçmiş veriler)
UPDATE orders o
SET 
  seller_has_own_courier = COALESCE(s.has_own_courier, FALSE)
FROM shops s
WHERE o.shop_id = s.id AND o.seller_has_own_courier IS NULL;

COMMENT ON COLUMN orders.seller_debt_amount IS 'Satıcının kapıda ödeme nedeniyle komisyon borcu';
COMMENT ON COLUMN orders.seller_credit_amount IS 'Satıcının online ödeme nedeniyle alacağı';
COMMENT ON COLUMN shops.commission_debt IS 'Satıcının toplam komisyon borcu (kapıda ödemeler)';
COMMENT ON COLUMN shops.admin_credit IS 'Satıcının adminden alacağı (online ödemeler)';

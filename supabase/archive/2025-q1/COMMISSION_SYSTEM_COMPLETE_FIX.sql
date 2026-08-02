-- KOMİSYON SİSTEMİ FİKS - CONSTRAINT HATASI ÇÖZÜLDÜ
-- Supabase SQL Editor'de kopyala-yapıştır yap, tümünü çalıştır

-- ═════════════════════════════════════════════════════════════════
-- 1. ADIM: CHECK CONSTRAINT'ı KONTROL ET
-- ═════════════════════════════════════════════════════════════════
-- Bu query ile mevcut constraint'ları görebilirsin:
-- SELECT constraint_name, constraint_definition FROM information_schema.table_constraints 
-- WHERE table_name = 'orders' AND constraint_type = 'CHECK';

-- ═════════════════════════════════════════════════════════════════
-- 2. ADIM: ESKI CONSTRAINT'I SİL
-- ═════════════════════════════════════════════════════════════════
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_commission_status_check;

-- ═════════════════════════════════════════════════════════════════
-- 3. ADIM: TÜM ESKİ TRIGGERS'I SİL
-- ═════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS calculate_order_commission ON orders CASCADE;
DROP TRIGGER IF EXISTS orders_auto_calculate_commission ON orders CASCADE;
DROP TRIGGER IF EXISTS update_shop_balance ON orders CASCADE;
DROP TRIGGER IF EXISTS validate_payout_request ON payout_requests CASCADE;
DROP TRIGGER IF EXISTS clear_shop_balance ON payout_requests CASCADE;

-- ═════════════════════════════════════════════════════════════════
-- 4. ADIM: TÜM ESKİ FUNCTION'LARI SİL
-- ═════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS calculate_order_commission() CASCADE;
DROP FUNCTION IF EXISTS auto_calculate_commission() CASCADE;
DROP FUNCTION IF EXISTS update_shop_balance() CASCADE;
DROP FUNCTION IF EXISTS validate_payout_request() CASCADE;
DROP FUNCTION IF EXISTS clear_shop_balance() CASCADE;

-- ═════════════════════════════════════════════════════════════════
-- 5. ADIM: YENİ CONSTRAINT EKLE
-- ═════════════════════════════════════════════════════════════════
ALTER TABLE orders 
ADD CONSTRAINT orders_commission_status_check 
CHECK (commission_status IN ('pending', 'paid', 'debt', 'credit', 'collected'));

-- ═════════════════════════════════════════════════════════════════
-- 6. ADIM: YENİ FUNCTION'LAR OLUŞTUR
-- ═════════════════════════════════════════════════════════════════

-- 6.1 KOMİSYON HESAPLAMA FUNCTION
CREATE OR REPLACE FUNCTION public.calculate_order_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_commission_rate NUMERIC;
  v_has_own_courier BOOLEAN;
  v_admin_commission NUMERIC;
BEGIN
  SELECT commission_rate, has_own_courier
  INTO v_commission_rate, v_has_own_courier
  FROM public.shops
  WHERE id = NEW.shop_id;

  v_commission_rate := COALESCE(v_commission_rate, 0.20);
  v_has_own_courier := COALESCE(v_has_own_courier, FALSE);

  v_admin_commission := NEW.subtotal * v_commission_rate;

  NEW.seller_has_own_courier := v_has_own_courier;
  NEW.admin_commission := v_admin_commission;

  IF v_has_own_courier THEN
    -- KURYESİ OLAN SATICI
    IF NEW.payment_method IN ('cash', 'card_on_delivery') THEN
      -- Kapıda ödeme: Satıcı parayı aldı, komisyon borcu
      NEW.admin_delivery_fee := 0;
      NEW.seller_debt_amount := v_admin_commission;
      NEW.seller_credit_amount := 0;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'debt';
    ELSE
      -- Online ödeme: Admin parayı aldı, satıcı alacaklı
      NEW.admin_delivery_fee := 0;
      NEW.seller_debt_amount := 0;
      NEW.seller_credit_amount := NEW.total - v_admin_commission;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'credit';
    END IF;
  ELSE
    -- KURYESİ OLMAYAN SATICI
    -- Tüm ödemeler admin'e gider, teslimat ücreti de admin alır
    -- Satıcıya sadece: subtotal - komisyon kalır
    NEW.admin_delivery_fee := NEW.delivery_fee; -- Teslimat admin'e
    NEW.seller_debt_amount := 0; -- Borç yok
    NEW.seller_credit_amount := NEW.subtotal - v_admin_commission; -- Sadece ürün tutarından komisyon kesilir
    NEW.seller_net_amount := NEW.subtotal - v_admin_commission;
    NEW.commission_status := 'credit'; -- Alacaklı
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- 6.2 KOMİSYON HESAPLAMA TRIGGER
CREATE TRIGGER calculate_order_commission
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.calculate_order_commission();

-- 6.3 SHOP BALANCE UPDATE FUNCTION
CREATE OR REPLACE FUNCTION public.update_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.shops
  SET 
    commission_debt = commission_debt + NEW.seller_debt_amount,
    admin_credit = admin_credit + NEW.seller_credit_amount,
    updated_at = NOW()
  WHERE id = NEW.shop_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- 6.4 SHOP BALANCE UPDATE TRIGGER
CREATE TRIGGER update_shop_balance
AFTER INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.update_shop_balance();

-- 6.5 PAYOUT REQUEST VALIDATION FUNCTION
CREATE OR REPLACE FUNCTION public.validate_payout_request()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_credit NUMERIC;
  v_commission_debt NUMERIC;
  v_net_receivable NUMERIC;
  v_has_own_courier BOOLEAN;
BEGIN
  SELECT admin_credit, commission_debt, has_own_courier
  INTO v_admin_credit, v_commission_debt, v_has_own_courier
  FROM public.shops
  WHERE id = NEW.shop_id;

  IF NOT v_has_own_courier THEN
    -- KURYESİ OLMAYAN SATICI: Direkt admin_credit
    NEW.net_receivable := v_admin_credit;
    NEW.commission_debt := 0;
    NEW.amount := v_admin_credit;
  ELSE
    -- KURYESİ OLAN SATICI
    -- Admin kredi: Online ödemelerden gelen tutar
    -- Komisyon borcu: Kapıda ödemelerden gelen kesinti
    v_net_receivable := v_admin_credit - v_commission_debt;
    
    NEW.net_receivable := v_net_receivable;
    NEW.commission_debt := v_commission_debt;
    NEW.admin_credit := v_admin_credit;
    NEW.amount := v_net_receivable;
    
    -- Borçlu bile olsa ödeme isteği oluşturabilir
    -- Ödeme isteğinde "Admine X₺ borcunuz var" yazısı gösterilecek
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- 6.6 PAYOUT REQUEST VALIDATION TRIGGER
CREATE TRIGGER validate_payout_request
BEFORE INSERT ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.validate_payout_request();

-- 6.7 CLEAR SHOP BALANCE FUNCTION
CREATE OR REPLACE FUNCTION public.clear_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status != 'approved' THEN
    UPDATE public.shops
    SET 
      commission_debt = 0,
      admin_credit = 0,
      updated_at = NOW()
    WHERE id = NEW.shop_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- 6.8 CLEAR SHOP BALANCE TRIGGER
CREATE TRIGGER clear_shop_balance
AFTER UPDATE ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.clear_shop_balance();

-- ═════════════════════════════════════════════════════════════════
-- 7. ADIM: ESKİ SİPARİŞLERİ DÜZELT (kuryesi olmayan satıcılar)
-- ═════════════════════════════════════════════════════════════════
UPDATE orders SET
  seller_credit_amount = GREATEST(0, subtotal - admin_commission),
  seller_debt_amount = 0,
  commission_status = 'collected',
  seller_net_amount = GREATEST(0, subtotal - admin_commission)
WHERE seller_has_own_courier = FALSE 
  AND commission_status IN ('pending', 'paid', 'collected')
  AND seller_credit_amount <= 0;

-- ═════════════════════════════════════════════════════════════════
-- 8. ADIM: SHOP BALANCE'LARI YENİDEN HESAPLA
-- ═════════════════════════════════════════════════════════════════
-- Tüm shop'ların balance'ını sıfırla
UPDATE shops
SET commission_debt = 0, admin_credit = 0;

-- Tüm siparişlerden topla ve yükle
UPDATE shops s
SET 
  commission_debt = COALESCE((
    SELECT SUM(seller_debt_amount)
    FROM orders o
    WHERE o.shop_id = s.id AND o.seller_debt_amount > 0
  ), 0),
  admin_credit = COALESCE((
    SELECT SUM(seller_credit_amount)
    FROM orders o
    WHERE o.shop_id = s.id AND o.seller_credit_amount > 0
  ), 0),
  updated_at = NOW()
WHERE EXISTS (
  SELECT 1 FROM orders WHERE shop_id = s.id
);

-- ═════════════════════════════════════════════════════════════════
-- 9. KONTROL: Mevcut durumu göster
-- ═════════════════════════════════════════════════════════════════

-- Kuryesi olmayan satıcılar
SELECT 
  'KURYESI OLMAYAN' as tip,
  s.id,
  s.name,
  s.has_own_courier,
  ROUND(s.commission_debt::numeric, 2) as commission_debt,
  ROUND(s.admin_credit::numeric, 2) as admin_credit,
  ROUND((s.admin_credit - s.commission_debt)::numeric, 2) as net_receivable,
  COUNT(DISTINCT o.id) as siparis_sayisi
FROM shops s
LEFT JOIN orders o ON s.id = o.shop_id
WHERE s.has_own_courier = FALSE OR s.has_own_courier IS NULL
GROUP BY s.id, s.name, s.has_own_courier
ORDER BY s.created_at DESC;

-- Kuryesi olan satıcılar
SELECT 
  'KURYESI OLAN' as tip,
  s.id,
  s.name,
  s.has_own_courier,
  ROUND(s.commission_debt::numeric, 2) as commission_debt,
  ROUND(s.admin_credit::numeric, 2) as admin_credit,
  ROUND((s.admin_credit - s.commission_debt)::numeric, 2) as net_receivable,
  COUNT(DISTINCT o.id) as siparis_sayisi
FROM shops s
LEFT JOIN orders o ON s.id = o.shop_id
WHERE s.has_own_courier = TRUE
GROUP BY s.id, s.name, s.has_own_courier
ORDER BY s.created_at DESC;

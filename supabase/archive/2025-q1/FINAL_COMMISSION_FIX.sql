-- ===================================================================
-- KOMİSYON SİSTEMİ - TAMAMEN FİKS MİGRATİON
-- Tüm eski triggers'ı sil, yenilerini kur, eski siparişleri düzelt
-- Supabase SQL Editor'de kopyala-yapıştır yap, tümünü çalıştır
-- ===================================================================

-- ═════════════════════════════════════════════════════════════════
-- 1. ADIM: TÜM ESKİ TRIGGERS'I SİL
-- ═════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS calculate_order_commission ON orders CASCADE;
DROP TRIGGER IF EXISTS orders_auto_calculate_commission ON orders CASCADE;
DROP TRIGGER IF EXISTS update_shop_balance ON orders CASCADE;
DROP TRIGGER IF EXISTS validate_payout_request ON payout_requests CASCADE;
DROP TRIGGER IF EXISTS clear_shop_balance ON payout_requests CASCADE;

-- ═════════════════════════════════════════════════════════════════
-- 2. ADIM: TÜM ESKİ FUNCTION'LARI SİL
-- ═════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS calculate_order_commission() CASCADE;
DROP FUNCTION IF EXISTS auto_calculate_commission() CASCADE;
DROP FUNCTION IF EXISTS update_shop_balance() CASCADE;
DROP FUNCTION IF EXISTS validate_payout_request() CASCADE;
DROP FUNCTION IF EXISTS clear_shop_balance() CASCADE;

-- ═════════════════════════════════════════════════════════════════
-- 3. ADIM: YENİ FUNCTION'LAR OLUŞTUR
-- ═════════════════════════════════════════════════════════════════

-- 3.1 KOMİSYON HESAPLAMA FUNCTION
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
    IF NEW.payment_method IN ('cash', 'card_on_delivery') THEN
      NEW.admin_delivery_fee := 0;
      NEW.seller_debt_amount := v_admin_commission;
      NEW.seller_credit_amount := 0;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'debt';
    ELSE
      NEW.admin_delivery_fee := 0;
      NEW.seller_debt_amount := 0;
      NEW.seller_credit_amount := NEW.total - v_admin_commission;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'credit';
    END IF;
  ELSE
    NEW.admin_delivery_fee := NEW.delivery_fee;
    NEW.seller_debt_amount := 0;
    NEW.seller_credit_amount := NEW.subtotal - v_admin_commission;
    NEW.seller_net_amount := NEW.subtotal - v_admin_commission;
    NEW.commission_status := 'credit';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- 3.2 KOMİSYON HESAPLAMA TRIGGER
CREATE TRIGGER calculate_order_commission
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.calculate_order_commission();

-- 3.3 SHOP BALANCE UPDATE FUNCTION
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

-- 3.4 SHOP BALANCE UPDATE TRIGGER
CREATE TRIGGER update_shop_balance
AFTER INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.update_shop_balance();

-- 3.5 PAYOUT REQUEST VALIDATION FUNCTION
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
    NEW.net_receivable := v_admin_credit;
    NEW.commission_debt := 0;
    NEW.amount := v_admin_credit;
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
$$ LANGUAGE plpgsql SET search_path = 'public';

-- 3.6 PAYOUT REQUEST VALIDATION TRIGGER
CREATE TRIGGER validate_payout_request
BEFORE INSERT ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.validate_payout_request();

-- 3.7 CLEAR SHOP BALANCE FUNCTION
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

-- 3.8 CLEAR SHOP BALANCE TRIGGER
CREATE TRIGGER clear_shop_balance
AFTER UPDATE ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.clear_shop_balance();

-- ═════════════════════════════════════════════════════════════════
-- 4. ADIM: ESKİ SİPARİŞLERİ DÜZELT (kuryesi olmayan satıcılar)
-- ═════════════════════════════════════════════════════════════════
UPDATE orders SET
  seller_credit_amount = subtotal - admin_commission,
  seller_debt_amount = 0,
  commission_status = 'credit',
  seller_net_amount = subtotal - admin_commission
WHERE seller_has_own_courier = FALSE 
  AND commission_status != 'credit';

-- ═════════════════════════════════════════════════════════════════
-- 5. ADIM: SHOP BALANCE'LARI YENİDEN HESAPLA
-- ═════════════════════════════════════════════════════════════════
-- Tüm shop'ların balance'ını sıfırla
UPDATE shops
SET commission_debt = 0, admin_credit = 0;

-- Tüm siparişlerden topla ve yükle
UPDATE shops s
SET 
  commission_debt = (
    SELECT COALESCE(SUM(seller_debt_amount), 0)
    FROM orders o
    WHERE o.shop_id = s.id AND o.seller_debt_amount > 0
  ),
  admin_credit = (
    SELECT COALESCE(SUM(seller_credit_amount), 0)
    FROM orders o
    WHERE o.shop_id = s.id AND o.seller_credit_amount > 0
  ),
  updated_at = NOW()
WHERE EXISTS (
  SELECT 1 FROM orders WHERE shop_id = s.id
);

-- ═════════════════════════════════════════════════════════════════
-- 6. KONTROL: Mevcut durumu göster
-- ═════════════════════════════════════════════════════════════════
SELECT 
  'KURYESI OLMAYAN SATICILAR' as kategori,
  s.id,
  s.name,
  s.has_own_courier,
  s.commission_debt,
  s.admin_credit,
  (s.admin_credit - s.commission_debt) as net_receivable,
  COUNT(o.id) as toplam_siparis
FROM shops s
LEFT JOIN orders o ON s.id = o.shop_id
WHERE s.has_own_courier = FALSE OR s.has_own_courier IS NULL
GROUP BY s.id, s.name, s.has_own_courier, s.commission_debt, s.admin_credit
ORDER BY s.created_at DESC;

SELECT 
  'KURYESI OLAN SATICILAR' as kategori,
  s.id,
  s.name,
  s.has_own_courier,
  s.commission_debt,
  s.admin_credit,
  (s.admin_credit - s.commission_debt) as net_receivable,
  COUNT(o.id) as toplam_siparis
FROM shops s
LEFT JOIN orders o ON s.id = o.shop_id
WHERE s.has_own_courier = TRUE
GROUP BY s.id, s.name, s.has_own_courier, s.commission_debt, s.admin_credit
ORDER BY s.created_at DESC;

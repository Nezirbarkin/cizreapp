-- KRİTİK FİKS: Çift trigger problemi ve eski commission function'larını temizle
-- Bu migration eski triggers'ı sil ve yeni olanları düzgün şekilde oluştur

-- 1. Tüm eski commission triggers'ını sil
DROP TRIGGER IF EXISTS calculate_order_commission ON orders CASCADE;
DROP TRIGGER IF EXISTS orders_auto_calculate_commission ON orders CASCADE;
DROP TRIGGER IF EXISTS update_shop_balance ON orders CASCADE;
DROP TRIGGER IF EXISTS validate_payout_request ON payout_requests CASCADE;
DROP TRIGGER IF EXISTS clear_shop_balance ON payout_requests CASCADE;

-- 2. Eski function'ları sil
DROP FUNCTION IF EXISTS calculate_order_commission() CASCADE;
DROP FUNCTION IF EXISTS auto_calculate_commission() CASCADE;
DROP FUNCTION IF EXISTS update_shop_balance() CASCADE;
DROP FUNCTION IF EXISTS validate_payout_request() CASCADE;
DROP FUNCTION IF EXISTS clear_shop_balance() CASCADE;

-- 3. Yeni commission calculation function - kuryesi olan/olmayan mantığı
CREATE OR REPLACE FUNCTION public.calculate_order_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_commission_rate NUMERIC;
  v_has_own_courier BOOLEAN;
  v_admin_commission NUMERIC;
BEGIN
  -- Satıcının bilgilerini al
  SELECT commission_rate, has_own_courier
  INTO v_commission_rate, v_has_own_courier
  FROM public.shops
  WHERE id = NEW.shop_id;

  -- Varsayılan değerler
  v_commission_rate := COALESCE(v_commission_rate, 0.20);
  v_has_own_courier := COALESCE(v_has_own_courier, FALSE);

  -- Komisyonu hesapla
  v_admin_commission := NEW.subtotal * v_commission_rate;

  NEW.seller_has_own_courier := v_has_own_courier;
  NEW.admin_commission := v_admin_commission;

  -- KURYESI OLAN SATICI
  IF v_has_own_courier THEN
    IF NEW.payment_method IN ('cash', 'card_on_delivery') THEN
      -- Kapıda ödeme: Komisyon borcu
      NEW.admin_delivery_fee := 0;
      NEW.seller_debt_amount := v_admin_commission;
      NEW.seller_credit_amount := 0;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'debt';
    ELSE
      -- Online ödeme: Alacak
      NEW.admin_delivery_fee := 0;
      NEW.seller_debt_amount := 0;
      NEW.seller_credit_amount := NEW.total - v_admin_commission;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'credit';
    END IF;
  ELSE
    -- KURYESI OLMAYAN SATICI - HER DURUMDA: Admin tüm parayı alır
    NEW.admin_delivery_fee := NEW.delivery_fee;
    NEW.seller_debt_amount := 0;
    NEW.seller_credit_amount := NEW.subtotal - v_admin_commission;
    NEW.seller_net_amount := NEW.subtotal - v_admin_commission;
    NEW.commission_status := 'credit';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- 4. Trigger'ı oluştur
CREATE TRIGGER calculate_order_commission
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.calculate_order_commission();

-- 5. Shop balance update function
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

CREATE TRIGGER update_shop_balance
AFTER INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.update_shop_balance();

-- 6. Payout request validation function
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
    -- Kuryesi olmayan: direkt alacak
    NEW.net_receivable := v_admin_credit;
    NEW.commission_debt := 0;
    NEW.amount := v_admin_credit;
  ELSE
    -- Kuryesi olan: Alacak - Borç
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

CREATE TRIGGER validate_payout_request
BEFORE INSERT ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.validate_payout_request();

-- 7. Clear shop balance function
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

CREATE TRIGGER clear_shop_balance
AFTER UPDATE ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.clear_shop_balance();

-- 8. Kontrol: Tüm triggers aktif olmalı
-- Bu query'yi çalıştırarak trigger'ların düzgün yüklü olduğunu doğrula:
-- SELECT tgname, tgenabled FROM pg_trigger WHERE tgrelid IN (SELECT oid FROM pg_class WHERE relname IN ('orders', 'payout_requests'));

-- Komisyon triggers için search_path problemini tam çöz
-- Bu migration'ı çalıştırmadan önce, trigger function'ları yeniden oluşturalım

-- 1. Eski trigger function'larını sil
DROP TRIGGER IF EXISTS calculate_order_commission ON orders CASCADE;
DROP TRIGGER IF EXISTS update_shop_balance ON orders CASCADE;
DROP FUNCTION IF EXISTS calculate_order_commission() CASCADE;
DROP FUNCTION IF EXISTS update_shop_balance() CASCADE;

-- 2. Yeni function'ları doğru search_path ile oluştur
CREATE OR REPLACE FUNCTION public.calculate_order_commission()
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
  FROM public.shops
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
$$ LANGUAGE plpgsql SET search_path = 'public';

CREATE TRIGGER calculate_order_commission
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.calculate_order_commission();

-- 3. Shop balance update trigger
CREATE OR REPLACE FUNCTION public.update_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Satıcının borç/alacak durumunu güncelle
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

-- 4. Validate payout request trigger
DROP TRIGGER IF EXISTS validate_payout_request ON payout_requests CASCADE;
DROP FUNCTION IF EXISTS validate_payout_request() CASCADE;

CREATE OR REPLACE FUNCTION public.validate_payout_request()
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
  FROM public.shops
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
$$ LANGUAGE plpgsql SET search_path = 'public';

CREATE TRIGGER validate_payout_request
BEFORE INSERT ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.validate_payout_request();

-- 5. Clear shop balance trigger
DROP TRIGGER IF EXISTS clear_shop_balance ON payout_requests CASCADE;
DROP FUNCTION IF EXISTS clear_shop_balance() CASCADE;

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

-- 6. Test: Kuryesi olmayan satıcılarının verisini kontrol et
-- Bu query'yi çalıştırarak mevcut durumu görebilirsin:
-- SELECT id, has_own_courier, commission_debt, admin_credit FROM shops WHERE has_own_courier = FALSE;

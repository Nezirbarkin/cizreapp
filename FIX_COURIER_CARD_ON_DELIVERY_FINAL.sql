-- ============================================================================
-- FIX: KURYESI OLAN SATICI - CARD_ON_DELIVERY KOMİSYON BORCU
-- ============================================================================
-- Sorun: Kuryesi OLAN satıcıda card_on_delivery ile sipariş verildiğinde
-- commission_debt (komisyon borcu) artmıyor, admin_credit artıyor
-- 
-- Çözüm: calculate_order_commission ve update_shop_balance fonksiyonlarını
-- tamamen yeniden yazıyoruz
-- ============================================================================

-- 1. Eski trigger'ları ve fonksiyonları kaldır
DROP TRIGGER IF EXISTS calculate_order_commission ON public.orders CASCADE;
DROP TRIGGER IF EXISTS update_shop_balance ON public.orders CASCADE;
DROP FUNCTION IF EXISTS public.calculate_order_commission() CASCADE;
DROP FUNCTION IF EXISTS public.update_shop_balance() CASCADE;

-- 2. KOMİSYON HESAPLAMA FONKSİYONU (BEFORE INSERT)
CREATE OR REPLACE FUNCTION public.calculate_order_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_commission_rate NUMERIC;
  v_has_own_courier BOOLEAN;
  v_admin_commission NUMERIC;
  v_delivery_fee NUMERIC;
BEGIN
  -- Satıcının bilgilerini al
  SELECT commission_rate, has_own_courier, delivery_fee
  INTO v_commission_rate, v_has_own_courier, v_delivery_fee
  FROM public.shops
  WHERE id = NEW.shop_id;

  -- Varsayılan değerler
  v_has_own_courier := COALESCE(v_has_own_courier, FALSE);
  v_delivery_fee := COALESCE(NEW.delivery_fee, v_delivery_fee, 0);
  
  -- commission_rate normalizasyonu
  v_commission_rate := COALESCE(v_commission_rate, 10);
  IF v_commission_rate > 1 THEN
    v_commission_rate := v_commission_rate / 100;
  END IF;
  
  -- Komisyon hesapla (subtotal üzerinden)
  v_admin_commission := NEW.subtotal * v_commission_rate;

  NEW.admin_commission := v_admin_commission;
  NEW.admin_delivery_fee := CASE WHEN v_has_own_courier THEN 0 ELSE v_delivery_fee END;
  NEW.seller_has_own_courier := v_has_own_courier;

  -- ====================================================================
  -- KURYESI OLAN SATICI
  -- ====================================================================
  IF v_has_own_courier THEN
    -- KAPIDA ÖDEMELER (cash, card_on_delivery, cardOnDelivery): Satıcı parayı alır, admin'e komisyon borcu
    IF NEW.payment_method IN ('cash', 'card_on_delivery', 'cardOnDelivery') THEN
      NEW.seller_cash_collected := NEW.total;
      NEW.seller_debt_amount := v_admin_commission;
      NEW.seller_credit_amount := 0;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'cash_collected';
    ELSE
      -- ONLINE ÖDEME: Admin parayı alır, satıcıya alacak
      NEW.seller_cash_collected := 0;
      NEW.seller_debt_amount := 0;
      NEW.seller_credit_amount := NEW.total - v_admin_commission;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'admin_collects';
    END IF;
  ELSE
    -- ====================================================================
    -- KURYESI OLMAYAN SATICI
    -- ====================================================================
    -- Admin tüm parayı toplar
    NEW.seller_cash_collected := 0;
    NEW.seller_debt_amount := 0;
    NEW.seller_credit_amount := NEW.subtotal - v_admin_commission;
    NEW.seller_net_amount := NEW.subtotal - v_admin_commission;
    NEW.commission_status := 'admin_collects';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

CREATE TRIGGER calculate_order_commission
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.calculate_order_commission();

-- 3. BAKİYE GÜNCELLEME FONKSİYONU (AFTER UPDATE ON DELIVERED)
CREATE OR REPLACE FUNCTION public.update_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Sadece teslim edilen siparişler için bakiye güncelle
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
    
    -- KURYESI OLAN SATICI + KAPIDA ÖDEME (cash_collected status)
    -- Komisyon borcu artar
    IF NEW.commission_status = 'cash_collected' THEN
      UPDATE public.shops
      SET 
        commission_debt = COALESCE(commission_debt, 0) + COALESCE(NEW.seller_debt_amount, 0),
        total_collected_cash = COALESCE(total_collected_cash, 0) + COALESCE(NEW.seller_cash_collected, 0),
        cash_payment_revenue = COALESCE(cash_payment_revenue, 0) + COALESCE(NEW.seller_net_amount, 0),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
      
    ELSE
      -- ONLINE ÖDEME veya KURYESİZ SATICI: Alacak artar
      UPDATE public.shops
      SET 
        admin_credit = COALESCE(admin_credit, 0) + COALESCE(NEW.seller_credit_amount, 0),
        online_payment_revenue = COALESCE(online_payment_revenue, 0) + COALESCE(NEW.seller_credit_amount, 0),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
    END IF;
    
    RAISE NOTICE 'Shop % bakiyesi güncellendi. Status: %, CommissionStatus: %, Debt: %, Credit: %', 
      NEW.shop_id, NEW.status, NEW.commission_status, NEW.seller_debt_amount, NEW.seller_credit_amount;
  END IF;

  -- İptal edilen siparişler için bakiyeyi geri al
  IF NEW.status = 'cancelled' AND OLD.status = 'delivered' THEN
    IF NEW.commission_status = 'cash_collected' THEN
      UPDATE public.shops
      SET 
        commission_debt = GREATEST(COALESCE(commission_debt, 0) - COALESCE(NEW.seller_debt_amount, 0), 0),
        total_collected_cash = GREATEST(COALESCE(total_collected_cash, 0) - COALESCE(NEW.seller_cash_collected, 0), 0),
        cash_payment_revenue = GREATEST(COALESCE(cash_payment_revenue, 0) - COALESCE(NEW.seller_net_amount, 0), 0),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
    ELSE
      UPDATE public.shops
      SET 
        admin_credit = GREATEST(COALESCE(admin_credit, 0) - COALESCE(NEW.seller_credit_amount, 0), 0),
        online_payment_revenue = GREATEST(COALESCE(online_payment_revenue, 0) - COALESCE(NEW.seller_credit_amount, 0), 0),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

CREATE TRIGGER update_shop_balance
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.update_shop_balance();

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'KURYESI OLAN SATICI - CARD_ON_DELIVERY DÜZELTİLDİ!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Kuryesi OLAN satıcılar:';
    RAISE NOTICE '  - cash: Satıcı parayı alır, admin''e KOMİSYON BORCU';
    RAISE NOTICE '  - card_on_delivery: Satıcı parayı alır, admin''e KOMİSYON BORCU';
    RAISE NOTICE '  - online: Admin parayı alır, satıcıya ALACAK';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Kuryesi OLMAYAN satıcılar:';
    RAISE NOTICE '  - Tüm ödemeler: Admin alır, satıcıya ALACAK';
    RAISE NOTICE '================================================================';
END $$;

-- ============================================================================
-- FIX: KAPIDA KART İLE ÖDEME - KURYESI OLAN SATICILAR İÇİN
-- ============================================================================
-- Sorun: card_on_delivery, kuryesi olan satıcılar için yanlış işleniyor
-- 
-- DOĞRU MANTIK:
-- - Kuryesi OLAN satıcı: cash ve card_on_delivery = Satıcı paranın tamamını alır
--   Admin sadece komisyonunu alır (satıcı borçlanır)
-- - Kuryesi OLAN satıcı: online = Admin parayı alır, satıcıya alacak
-- - Kuryesi OLMAYAN satıcı: Tüm ödemeler admin'e gider
-- ============================================================================

DROP TRIGGER IF EXISTS calculate_order_commission ON public.orders CASCADE;
DROP FUNCTION IF EXISTS public.calculate_order_commission() CASCADE;

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

  -- ====================================================================
  -- KURYESI OLAN SATICI
  -- ====================================================================
  IF v_has_own_courier THEN
    -- KAPIDA ÖDEMELER (cash VE card_on_delivery): Satıcı parayı alır
    IF NEW.payment_method IN ('cash', 'card_on_delivery') THEN
      NEW.seller_has_own_courier := TRUE;
      NEW.admin_commission := v_admin_commission;
      NEW.admin_delivery_fee := 0;
      NEW.seller_cash_collected := NEW.total;
      NEW.seller_debt_amount := v_admin_commission;
      NEW.seller_credit_amount := 0;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'cash_collected';
    ELSE
      -- ONLINE ÖDEME: Admin parayı alır, satıcıya alacak
      NEW.seller_has_own_courier := TRUE;
      NEW.admin_commission := v_admin_commission;
      NEW.admin_delivery_fee := 0;
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
    -- Admin tüm parayı toplar, komisyon + teslimat ücreti kesilir
    NEW.seller_has_own_courier := FALSE;
    NEW.admin_commission := v_admin_commission;
    NEW.admin_delivery_fee := v_delivery_fee;
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

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'KAPIDA KART İLE ÖDEME DÜZELTME TAMAMLANDI!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Kuryesi OLAN satıcılar:';
    RAISE NOTICE '  - cash: Satıcı parayı alır, admin''e komisyon borcu';
    RAISE NOTICE '  - card_on_delivery: Satıcı parayı alır, admin''e komisyon borcu (DÜZELTİLDİ)';
    RAISE NOTICE '  - online: Admin parayı alır, satıcıya alacak';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Kuryesi OLMAYAN satıcılar:';
    RAISE NOTICE '  - Tüm ödemeler: Admin alır, komisyon+teslimat kesilir';
    RAISE NOTICE '================================================================';
END $$;

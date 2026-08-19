-- Kuryesiz satıcıda kapıda ödeme kazancının doğru kategoride gösterilmesi
-- Sorun: Kuryesiz satıcıda kapıda nakit/kart ödeme yapıldığında
-- kazanç online_payment_revenue'a ekleniyor, cash_payment_revenue'ya eklenmeli
--
-- Çözüm: update_shop_balance fonksiyonunda payment_method da kontrol edilmeli

CREATE OR REPLACE FUNCTION public.update_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Sadece teslim edilen siparişler için bakiye güncelle
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
    
    -- Kuryeli satıcı ve kapıda ödeme: Nakit gelir
    IF NEW.commission_status = 'cash_collected' THEN
      UPDATE public.shops
      SET 
        commission_debt = COALESCE(commission_debt, 0) + COALESCE(NEW.seller_debt_amount, 0),
        total_collected_cash = COALESCE(total_collected_cash, 0) + COALESCE(NEW.seller_cash_collected, 0),
        cash_payment_revenue = COALESCE(cash_payment_revenue, 0) + COALESCE(NEW.seller_net_amount, 0),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
      
    -- Kuryesiz satıcı ve KAPIDA ÖDEME: Nakit gelir (admin toplar ama nakit)
    ELSIF NEW.payment_method IN ('cash', 'card_on_delivery') THEN
      UPDATE public.shops
      SET 
        admin_credit = COALESCE(admin_credit, 0) + COALESCE(NEW.seller_credit_amount, 0),
        cash_payment_revenue = COALESCE(cash_payment_revenue, 0) + COALESCE(NEW.seller_net_amount, 0),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
      
    -- Kuryesiz satıcı ve ONLINE ÖDEME: Online gelir
    ELSE
      UPDATE public.shops
      SET 
        admin_credit = COALESCE(admin_credit, 0) + COALESCE(NEW.seller_credit_amount, 0),
        online_payment_revenue = COALESCE(online_payment_revenue, 0) + COALESCE(NEW.seller_credit_amount, 0),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
    END IF;
    
    RAISE NOTICE 'Shop % bakiyesi güncellendi. Status: %, Payment: %, Credit: %', 
      NEW.shop_id, NEW.commission_status, NEW.payment_method, NEW.seller_credit_amount;
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
    ELSIF NEW.payment_method IN ('cash', 'card_on_delivery') THEN
      -- Kuryesiz kapıda ödeme iptal
      UPDATE public.shops
      SET 
        admin_credit = GREATEST(COALESCE(admin_credit, 0) - COALESCE(NEW.seller_credit_amount, 0), 0),
        cash_payment_revenue = GREATEST(COALESCE(cash_payment_revenue, 0) - COALESCE(NEW.seller_net_amount, 0), 0),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
    ELSE
      -- Online ödeme iptal
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
$$ LANGUAGE plpgsql SET search_path = 'public';

-- =====================================================
-- MEVCUT VERİLERİ DÜZELT
-- =====================================================
-- Tüm bakiyeleri sıfırla ve yeniden hesapla
UPDATE public.shops
SET
  admin_credit = 0,
  commission_debt = 0,
  total_collected_cash = 0,
  cash_payment_revenue = 0,
  online_payment_revenue = 0
WHERE TRUE;

-- 1. Kuryeli satıcı + kapıda ödeme (cash_collected)
UPDATE public.shops s
SET
  commission_debt = COALESCE(sub.total_debt, 0),
  total_collected_cash = COALESCE(sub.total_cash, 0),
  cash_payment_revenue = COALESCE(sub.total_net, 0)
FROM (
  SELECT
    o.shop_id,
    SUM(COALESCE(o.seller_debt_amount, 0)) as total_debt,
    SUM(COALESCE(o.seller_cash_collected, 0)) as total_cash,
    SUM(COALESCE(o.seller_net_amount, 0)) as total_net
  FROM public.orders o
  WHERE o.status = 'delivered'
    AND o.commission_status = 'cash_collected'
  GROUP BY o.shop_id
) sub
WHERE s.id = sub.shop_id;

-- 2. Kuryesiz satıcı + kapıda ödeme → cash_payment_revenue
UPDATE public.shops s
SET
  admin_credit = COALESCE(s.admin_credit, 0) + COALESCE(sub.total_credit, 0),
  cash_payment_revenue = COALESCE(s.cash_payment_revenue, 0) + COALESCE(sub.total_net, 0)
FROM (
  SELECT
    o.shop_id,
    SUM(COALESCE(o.seller_credit_amount, 0)) as total_credit,
    SUM(COALESCE(o.seller_net_amount, 0)) as total_net
  FROM public.orders o
  WHERE o.status = 'delivered'
    AND o.commission_status = 'admin_collects'
    AND o.payment_method IN ('cash', 'card_on_delivery')
  GROUP BY o.shop_id
) sub
WHERE s.id = sub.shop_id;

-- 3. Tüm online ödemeler → online_payment_revenue
UPDATE public.shops s
SET
  admin_credit = COALESCE(s.admin_credit, 0) + COALESCE(sub.total_credit, 0),
  online_payment_revenue = COALESCE(s.online_payment_revenue, 0) + COALESCE(sub.total_credit, 0)
FROM (
  SELECT
    o.shop_id,
    SUM(COALESCE(o.seller_credit_amount, 0)) as total_credit
  FROM public.orders o
  WHERE o.status = 'delivered'
    AND o.commission_status = 'admin_collects'
    AND o.payment_method NOT IN ('cash', 'card_on_delivery')
  GROUP BY o.shop_id
) sub
WHERE s.id = sub.shop_id;

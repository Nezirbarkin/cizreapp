-- ============================================================================
-- FIX: Payment Method Case Sensitivity (cardOnDelivery vs card_on_delivery)
-- ============================================================================
-- Problem: Dart "cardOnDelivery" gönderiyor ama SQL "card_on_delivery" arıyor
-- Sonuç: Kapıda kart ödemeleri online_payment_revenue'ya düşüyor (YANLIŞ!)
-- Çözüm: SQL trigger'da her iki formatı da destekle
-- ============================================================================

-- 1. update_shop_balance fonksiyonunu güncelle
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
      
    -- Kuryesiz satıcı ve KAPIDA ÖDEME (cash, cardOnDelivery, card_on_delivery): Nakit gelir
    ELSIF NEW.payment_method IN ('cash', 'card_on_delivery', 'cardOnDelivery') THEN
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
    ELSIF NEW.payment_method IN ('cash', 'card_on_delivery', 'cardOnDelivery') THEN
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

-- 2. Mevcut verileri düzelt (cardOnDelivery olanları card_on_delivery olarak güncelle)
UPDATE public.orders 
SET payment_method = 'card_on_delivery' 
WHERE payment_method = 'cardOnDelivery';

-- 3. Mevcut kazanç verilerini yeniden hesapla
-- Önce sıfırla
UPDATE public.shops
SET 
  cash_payment_revenue = 0,
  online_payment_revenue = 0,
  admin_credit = 0,
  total_collected_cash = 0;

-- Kuryeli satıcılar için cash_collected siparişleri
UPDATE public.shops s
SET 
  commission_debt = COALESCE(s.commission_debt, 0) + COALESCE(sub.total_debt, 0),
  total_collected_cash = COALESCE(sub.total_cash, 0),
  cash_payment_revenue = COALESCE(s.cash_payment_revenue, 0) + COALESCE(sub.total_revenue, 0)
FROM (
  SELECT 
    o.shop_id,
    SUM(o.seller_debt_amount) as total_debt,
    SUM(o.seller_cash_collected) as total_cash,
    SUM(o.seller_net_amount) as total_revenue
  FROM public.orders o
  WHERE o.status = 'delivered'
    AND o.commission_status = 'cash_collected'
  GROUP BY o.shop_id
) sub
WHERE s.id = sub.shop_id;

-- Kuryesiz satıcılar + kapıda ödeme → cash_payment_revenue
UPDATE public.shops s
SET 
  admin_credit = COALESCE(s.admin_credit, 0) + COALESCE(sub.total_credit, 0),
  cash_payment_revenue = COALESCE(s.cash_payment_revenue, 0) + COALESCE(sub.total_net, 0)
FROM (
  SELECT 
    o.shop_id,
    SUM(o.seller_credit_amount) as total_credit,
    SUM(o.seller_net_amount) as total_net
  FROM public.orders o
  WHERE o.status = 'delivered'
    AND o.commission_status = 'admin_collects'
    AND o.payment_method IN ('cash', 'card_on_delivery')
  GROUP BY o.shop_id
) sub
WHERE s.id = sub.shop_id;

-- Online ödemeler → online_payment_revenue
UPDATE public.shops s
SET 
  admin_credit = COALESCE(s.admin_credit, 0) + COALESCE(sub.total_credit, 0),
  online_payment_revenue = COALESCE(s.online_payment_revenue, 0) + COALESCE(sub.total_credit, 0)
FROM (
  SELECT 
    o.shop_id,
    SUM(o.seller_credit_amount) as total_credit
  FROM public.orders o
  WHERE o.status = 'delivered'
    AND o.commission_status = 'admin_collects'
    AND o.payment_method NOT IN ('cash', 'card_on_delivery')
  GROUP BY o.shop_id
) sub
WHERE s.id = sub.shop_id;

SELECT '✅ Payment method case sensitivity düzeltildi' as result;
SELECT '✅ Mevcut siparişler düzeltildi: cardOnDelivery → card_on_delivery' as result;
SELECT '✅ Kazanç verileri yeniden hesaplandı' as result;

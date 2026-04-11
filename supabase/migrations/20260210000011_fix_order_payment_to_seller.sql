-- ########################################################
-- # SİPARİŞ ÖDEMELERİNİN SATICIYA YANSIMADIĞI SORUNUN DÜZELTMESİ
-- ########################################################
-- Sorunlar:
-- 1. commission_rate format tutarsızlığı (0.20 vs 20 gibi)
-- 2. Trigger'ların çakışması
-- 3. Mevcut siparişlerin bakiyeye yansıtılmamış olması

-- =====================================================
-- ADIM 1: TÜM ESKİ TRIGGER'LARI TEMİZLE
-- =====================================================
DROP TRIGGER IF EXISTS calculate_order_commission ON public.orders CASCADE;
DROP TRIGGER IF EXISTS update_shop_balance ON public.orders CASCADE;
DROP TRIGGER IF EXISTS auto_calculate_commission ON public.orders CASCADE;

DROP FUNCTION IF EXISTS public.calculate_order_commission() CASCADE;
DROP FUNCTION IF EXISTS public.update_shop_balance() CASCADE;
DROP FUNCTION IF EXISTS public.auto_calculate_commission() CASCADE;

-- =====================================================
-- ADIM 2: KOMİSYON HESAPLAMA FONKSİYONU (YENİ SİPARİŞ)
-- =====================================================
-- commission_rate: shops tablosunda 10, 15, 20 gibi yüzdelik değer tutulur
-- Hesaplama: total * (commission_rate / 100)
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
  
  -- commission_rate normalizasyonu:
  -- Eğer 1'den büyükse yüzdelik (10 = %10), küçükse ondalık (0.10 = %10)
  v_commission_rate := COALESCE(v_commission_rate, 10);
  IF v_commission_rate > 1 THEN
    -- Yüzdelik değer (10, 15, 20 gibi) → ondalığa çevir
    v_commission_rate := v_commission_rate / 100;
  END IF;
  
  -- Komisyon hesapla (subtotal üzerinden, teslimat hariç)
  v_admin_commission := NEW.subtotal * v_commission_rate;

  -- Kuryesi OLAN SATICI
  IF v_has_own_courier THEN
    IF NEW.payment_method IN ('cash', 'card_on_delivery') THEN
      -- Kapıda ödeme: Satıcı parayı direkt müşteriden alır
      NEW.seller_has_own_courier := TRUE;
      NEW.admin_commission := v_admin_commission;
      NEW.admin_delivery_fee := 0;
      NEW.seller_cash_collected := NEW.total;
      NEW.seller_debt_amount := v_admin_commission;
      NEW.seller_credit_amount := 0;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'cash_collected';
    ELSE
      -- Online ödeme: Para admin'e gider, satıcıya alacak
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
    -- KURYESI OLMAYAN SATICI
    -- Admin tüm parayı toplar
    -- Komisyon + Teslimat ücreti kesilir
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
$$ LANGUAGE plpgsql SET search_path = 'public';

-- Trigger oluştur
CREATE TRIGGER calculate_order_commission
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.calculate_order_commission();

-- =====================================================
-- ADIM 3: SİPARİŞ TESLİM EDİLDİĞİNDE BAKİYE GÜNCELLEME
-- =====================================================
CREATE OR REPLACE FUNCTION public.update_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Sadece teslim edilen siparişler için bakiye güncelle
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
    
    IF NEW.commission_status = 'cash_collected' THEN
      -- Kapıda tahsilat: Komisyon borç artar, nakit gelir artar
      UPDATE public.shops
      SET 
        commission_debt = COALESCE(commission_debt, 0) + COALESCE(NEW.seller_debt_amount, 0),
        total_collected_cash = COALESCE(total_collected_cash, 0) + COALESCE(NEW.seller_cash_collected, 0),
        cash_payment_revenue = COALESCE(cash_payment_revenue, 0) + COALESCE(NEW.seller_net_amount, 0),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
    ELSE
      -- Online/Admin collects: Alacak artar
      UPDATE public.shops
      SET 
        admin_credit = COALESCE(admin_credit, 0) + COALESCE(NEW.seller_credit_amount, 0),
        online_payment_revenue = COALESCE(online_payment_revenue, 0) + COALESCE(NEW.seller_credit_amount, 0),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
    END IF;
    
    RAISE NOTICE 'Shop % bakiyesi güncellendi. Status: %, Credit: %, Debt: %', 
      NEW.shop_id, NEW.commission_status, NEW.seller_credit_amount, NEW.seller_debt_amount;
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
$$ LANGUAGE plpgsql SET search_path = 'public';

CREATE TRIGGER update_shop_balance
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.update_shop_balance();

-- =====================================================
-- ADIM 4: MEVCUT TESLİM EDİLMİŞ SİPARİŞLERİ DÜZELT
-- =====================================================
-- Önce tüm shops bakiyelerini sıfırla (temiz başlangıç)
UPDATE public.shops
SET 
  admin_credit = 0,
  commission_debt = 0,
  total_collected_cash = 0,
  cash_payment_revenue = 0,
  online_payment_revenue = 0
WHERE TRUE;

-- Mevcut siparişlerdeki commission_rate'i düzelt
-- (eğer yanlış hesaplanmışsa)
UPDATE public.orders o
SET
  admin_commission = CASE
    WHEN s.commission_rate IS NOT NULL AND s.commission_rate > 1 THEN
      o.subtotal * (s.commission_rate / 100)
    WHEN s.commission_rate IS NOT NULL AND s.commission_rate <= 1 THEN
      o.subtotal * s.commission_rate
    ELSE
      o.subtotal * 0.10
  END,
  seller_net_amount = CASE
    WHEN o.seller_has_own_courier = TRUE THEN
      o.total - CASE
        WHEN s.commission_rate > 1 THEN o.subtotal * (s.commission_rate / 100)
        WHEN s.commission_rate <= 1 THEN o.subtotal * s.commission_rate
        ELSE o.subtotal * 0.10
      END
    ELSE
      o.subtotal - CASE
        WHEN s.commission_rate > 1 THEN o.subtotal * (s.commission_rate / 100)
        WHEN s.commission_rate <= 1 THEN o.subtotal * s.commission_rate
        ELSE o.subtotal * 0.10
      END
  END,
  seller_credit_amount = CASE
    WHEN o.commission_status = 'admin_collects' THEN
      CASE
        WHEN o.seller_has_own_courier = TRUE THEN
          o.total - CASE
            WHEN s.commission_rate > 1 THEN o.subtotal * (s.commission_rate / 100)
            ELSE o.subtotal * COALESCE(s.commission_rate, 0.10)
          END
        ELSE
          o.subtotal - CASE
            WHEN s.commission_rate > 1 THEN o.subtotal * (s.commission_rate / 100)
            ELSE o.subtotal * COALESCE(s.commission_rate, 0.10)
          END
      END
    ELSE 0
  END,
  seller_debt_amount = CASE
    WHEN o.commission_status = 'cash_collected' THEN
      CASE
        WHEN s.commission_rate > 1 THEN o.subtotal * (s.commission_rate / 100)
        ELSE o.subtotal * COALESCE(s.commission_rate, 0.10)
      END
    ELSE 0
  END,
  seller_cash_collected = CASE
    WHEN o.commission_status = 'cash_collected' THEN o.total
    ELSE 0
  END
FROM public.shops s
WHERE o.shop_id = s.id
  AND o.status != 'cancelled';

-- Şimdi teslim edilen siparişlerin bakiyelerini yeniden hesapla
-- Cash collected siparişler
UPDATE public.shops s
SET 
  commission_debt = COALESCE(sub.total_debt, 0),
  total_collected_cash = COALESCE(sub.total_cash, 0),
  cash_payment_revenue = COALESCE(sub.total_revenue, 0)
FROM (
  SELECT 
    shop_id,
    SUM(COALESCE(seller_debt_amount, 0)) as total_debt,
    SUM(COALESCE(seller_cash_collected, 0)) as total_cash,
    SUM(COALESCE(seller_net_amount, 0)) as total_revenue
  FROM public.orders
  WHERE status = 'delivered' 
    AND commission_status = 'cash_collected'
  GROUP BY shop_id
) sub
WHERE s.id = sub.shop_id;

-- Admin collects siparişler
UPDATE public.shops s
SET 
  admin_credit = COALESCE(admin_credit, 0) + COALESCE(sub.total_credit, 0),
  online_payment_revenue = COALESCE(online_payment_revenue, 0) + COALESCE(sub.total_credit, 0)
FROM (
  SELECT 
    shop_id,
    SUM(COALESCE(seller_credit_amount, 0)) as total_credit
  FROM public.orders
  WHERE status = 'delivered' 
    AND commission_status = 'admin_collects'
  GROUP BY shop_id
) sub
WHERE s.id = sub.shop_id;

-- =====================================================
-- ADIM 5: commission_status constraint güncelle
-- =====================================================
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_commission_status_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_commission_status_check
  CHECK (commission_status IN ('pending', 'debt', 'credit', 'cash_collected', 'admin_collects'));

-- =====================================================
-- ADIM 6: PERFORMANS İNDEKSLERİ
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_orders_commission_status ON public.orders(commission_status) WHERE status = 'delivered';
CREATE INDEX IF NOT EXISTS idx_shops_courier_balance ON public.shops(has_own_courier, admin_credit, commission_debt);
CREATE INDEX IF NOT EXISTS idx_orders_shop_status ON public.orders(shop_id, status);

-- =====================================================
-- DOĞRULAMA SORGUSU (Manuel çalıştırın)
-- =====================================================
-- SELECT 
--   s.name,
--   s.admin_credit,
--   s.commission_debt,
--   s.cash_payment_revenue,
--   s.online_payment_revenue,
--   s.total_collected_cash,
--   COUNT(o.id) as delivered_orders
-- FROM shops s
-- LEFT JOIN orders o ON o.shop_id = s.id AND o.status = 'delivered'
-- GROUP BY s.id, s.name, s.admin_credit, s.commission_debt, s.cash_payment_revenue, s.online_payment_revenue, s.total_collected_cash
-- ORDER BY s.name;

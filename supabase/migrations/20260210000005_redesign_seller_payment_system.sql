-- Satıcı Ödeme Sistemi Yeniden Tasarım
-- Daha net komisyon ve ödeme mantığı için trigger güncellemeleri

-- ############################################
-- # KURYE DEĞİŞİKLİĞİ GEÇİŞ MANTIĞI
-- ############################################
-- Kuryesi OLAN → OLMAYAN geçişi:
-- 1. Mevcut komisyon borcu kalır (kapıda tahsilattan)
-- 2. Mevcut alacaklar kalır
-- 3. Yeni siparişler "kuryesiz" sistemle hesaplanır
--
-- Kuryesi OLMAYAN → OLAN geçişi:
-- 1. Mevcut alacaklar kalır
-- 2. Yeni siparişler "kuryeli" sistemle hesaplanır

-- 1. Önce mevcut trigger'ları kaldır
DROP TRIGGER IF EXISTS calculate_order_commission ON public.orders CASCADE;
DROP TRIGGER IF EXISTS update_shop_balance ON public.orders CASCADE;
DROP TRIGGER IF EXISTS validate_payout_request ON public.payout_requests CASCADE;
DROP TRIGGER IF EXISTS clear_shop_balance ON public.payout_requests CASCADE;

-- 2. Eski function'ları kaldır
DROP FUNCTION IF EXISTS public.calculate_order_commission() CASCADE;
DROP FUNCTION IF EXISTS public.update_shop_balance() CASCADE;
DROP FUNCTION IF EXISTS public.validate_payout_request() CASCADE;
DROP FUNCTION IF EXISTS public.clear_shop_balance() CASCADE;

-- 3. Shops tablosuna yeni kolonlar ekle (backward compatible)
ALTER TABLE public.shops 
  ADD COLUMN IF NOT EXISTS total_collected_cash NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cash_payment_revenue NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS online_payment_revenue NUMERIC DEFAULT 0;

-- 4. Orders tablosuna yeni kolon ekle (backward compatible)
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS seller_cash_collected NUMERIC DEFAULT 0;

-- 5. YENİ COMMISSION CALCULATION FUNCTION
-- Mantık:
-- - Kuryesi OLAN + Kapıda ödeme: Satıcı parayı alır, komisyon borç olarak kaydedilir
-- - Kuryesi OLAN + Online ödeme: Admin parayı alır, satıcıya alacak kaydedilir
-- - Kuryesi OLMAYAN: Admin tüm parayı alır, komisyon + teslimat kesilir, net alacak kaydedilir
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
  v_commission_rate := COALESCE(v_commission_rate, 0.20);
  v_has_own_courier := COALESCE(v_has_own_courier, FALSE);
  v_delivery_fee := COALESCE(NEW.delivery_fee, v_delivery_fee, 0);

  -- Komisyon hesapla (total üzerinden)
  v_admin_commission := NEW.total * v_commission_rate;

  -- Kuryesi OLAN SATICI
  IF v_has_own_courier THEN
    IF NEW.payment_method IN ('cash', 'card_on_delivery') THEN
      -- Kapıda ödeme: Satıcı parayı direkt müşteriden alır
      -- Sadece komisyon borç olarak kaydedilir
      NEW.seller_has_own_courier := TRUE;
      NEW.admin_commission := v_admin_commission;
      NEW.admin_delivery_fee := 0;
      NEW.seller_cash_collected := NEW.total;  -- Satıcı parayı topladı
      NEW.seller_debt_amount := v_admin_commission;  -- Komisyon borcu
      NEW.seller_credit_amount := 0;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'cash_collected';  -- Kapıda tahsilat
    ELSE
      -- Online ödeme: Para admin'e gider, satıcıya alacak
      NEW.seller_has_own_courier := TRUE;
      NEW.admin_commission := v_admin_commission;
      NEW.admin_delivery_fee := 0;
      NEW.seller_cash_collected := 0;
      NEW.seller_debt_amount := 0;
      NEW.seller_credit_amount := NEW.total - v_admin_commission;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'admin_collects';  -- Admin topladı
    END IF;
  ELSE
    -- KURYESI OLMAYAN SATICI - Her durumda
    -- Admin tüm parayı toplar (hem online hem kapıda)
    -- Komisyon + Teslimat ücreti kesilir
    NEW.seller_has_own_courier := FALSE;
    NEW.admin_commission := v_admin_commission;
    NEW.admin_delivery_fee := v_delivery_fee;  -- Admin teslimat ücretini alır
    NEW.seller_cash_collected := 0;  -- Satıcı hiçbir para toplamaz
    NEW.seller_debt_amount := 0;
    NEW.seller_credit_amount := NEW.total - v_admin_commission - v_delivery_fee;
    NEW.seller_net_amount := NEW.total - v_admin_commission - v_delivery_fee;
    NEW.commission_status := 'admin_collects';  -- Admin topladı
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- Trigger'ı oluştur
CREATE TRIGGER calculate_order_commission
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.calculate_order_commission();

-- 6. YENİ SHOP BALANCE UPDATE FUNCTION
-- Sipariş durumuna göre bakiyeyi güncelle
CREATE OR REPLACE FUNCTION public.update_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Sadece teslim edilen siparişler için bakiye güncelle
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
    IF NEW.commission_status = 'cash_collected' THEN
      -- Kapıda tahsilat: Komisyon borç artar, nakit gelir artar
      UPDATE public.shops
      SET 
        commission_debt = commission_debt + NEW.seller_debt_amount,
        total_collected_cash = total_collected_cash + NEW.seller_cash_collected,
        cash_payment_revenue = cash_payment_revenue + (NEW.total - NEW.seller_debt_amount),
        updated_at = NOW()
      WHERE id = NEW.shop_id;
    ELSE
      -- Online/Admin collects: Alacak artar
      UPDATE public.shops
      SET 
        admin_credit = admin_credit + NEW.seller_credit_amount,
        online_payment_revenue = online_payment_revenue + NEW.seller_credit_amount,
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

-- 7. YENİ PAYOUT REQUEST VALIDATION FUNCTION
CREATE OR REPLACE FUNCTION public.validate_payout_request()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_credit NUMERIC;
  v_commission_debt NUMERIC;
  v_net_receivable NUMERIC;
  v_has_own_courier BOOLEAN;
  v_pending_requests_total NUMERIC;
BEGIN
  SELECT admin_credit, commission_debt, has_own_courier
  INTO v_admin_credit, v_commission_debt, v_has_own_courier
  FROM public.shops
  WHERE id = NEW.shop_id;

  -- Bekleyen ödeme isteklerinin toplamını hesapla
  SELECT COALESCE(SUM(total_amount), 0)
  INTO v_pending_requests_total
  FROM public.payout_requests
  WHERE shop_id = NEW.shop_id AND status = 'pending';

  -- Net ödenebilir tutarı hesapla
  IF v_has_own_courier THEN
    -- Kuryesi OLAN: Alacak - Borç
    v_net_receivable := v_admin_credit - v_commission_debt - v_pending_requests_total;
    
    IF v_net_receivable <= 0 THEN
      RAISE EXCEPTION 'Ödeme isteği oluşturulamaz. Komisyon borcunuz: ₺%, Online ödeme alacağınız: ₺%, Bekleyen istekler: ₺%', 
        v_commission_debt, v_admin_credit, v_pending_requests_total;
    END IF;

    NEW.net_receivable := v_net_receivable;
    NEW.commission_debt := v_commission_debt;
    NEW.admin_credit := v_admin_credit;
  ELSE
    -- Kuryesi OLMAYAN: Direkt alacak (teslimat ve komisyon zaten düşüldü)
    v_net_receivable := v_admin_credit - v_pending_requests_total;
    
    IF v_net_receivable <= 0 THEN
      RAISE EXCEPTION 'Ödeme isteği oluşturulamaz. Bekleyen ödeme alacağınız: ₺%, Bekleyen istekler: ₺%', 
        v_admin_credit, v_pending_requests_total;
    END IF;

    NEW.net_receivable := v_net_receivable;
    NEW.commission_debt := 0;
    NEW.admin_credit := v_admin_credit;
  END IF;

  -- İstenen tutar kontrolü
  IF NEW.amount > v_net_receivable THEN
    RAISE EXCEPTION 'İstediğiniz tutar (₺%) net ödenebilir tutarınızdan (₺%) daha fazla.', 
      NEW.amount, v_net_receivable;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

CREATE TRIGGER validate_payout_request
BEFORE INSERT ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.validate_payout_request();

-- 8. YENİ CLEAR SHOP BALANCE FUNCTION
-- Ödeme onaylandığında bakiyeleri güncelle
CREATE OR REPLACE FUNCTION public.clear_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status != 'approved') THEN
    -- Shop'tan düşülecek tutarları hesapla
    DECLARE
      v_shop_has_courier BOOLEAN;
      v_commission_debt NUMERIC;
      v_admin_credit NUMERIC;
    BEGIN
      SELECT has_own_courier, commission_debt, admin_credit
      INTO v_shop_has_courier, v_commission_debt, v_admin_credit
      FROM public.shops
      WHERE id = NEW.shop_id;

      IF v_shop_has_courier THEN
        -- Kuryesi olan: Hem borcu hem alacağı sıfırla
        UPDATE public.shops
        SET 
          commission_debt = 0,
          admin_credit = 0,
          total_paid = total_paid + NEW.amount,
          updated_at = NOW()
        WHERE id = NEW.shop_id;
      ELSE
        -- Kuryesi olmayan: Sadece alacağı düş
        UPDATE public.shops
        SET 
          admin_credit = admin_credit - NEW.amount,
          total_paid = total_paid + NEW.amount,
          updated_at = NOW()
        WHERE id = NEW.shop_id;
      END IF;
    END;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

CREATE TRIGGER clear_shop_balance
AFTER UPDATE ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.clear_shop_balance();

-- 9. İndeksler for performance
CREATE INDEX IF NOT EXISTS idx_orders_commission_status ON public.orders(commission_status) WHERE status = 'delivered';
CREATE INDEX IF NOT EXISTS idx_shops_courier_balance ON public.shops(has_own_courier, admin_credit, commission_debt);

-- ############################################
-- # KURYE DURUMU DEĞİŞİKLİĞİ TRİGGER
-- ############################################
-- Satıcı kurye durumunu değiştirdiğinde geçiş işlemleri

-- 10. Kurye değişikliği için log tablosu
CREATE TABLE IF NOT EXISTS public.courier_status_changes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID REFERENCES public.shops(id) ON DELETE CASCADE,
  previous_status BOOLEAN,
  new_status BOOLEAN,
  admin_credit_at_change NUMERIC DEFAULT 0,
  commission_debt_at_change NUMERIC DEFAULT 0,
  cash_revenue_at_change NUMERIC DEFAULT 0,
  online_revenue_at_change NUMERIC DEFAULT 0,
  changed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  notes TEXT
);

-- 11. Kurye değişikliği function
CREATE OR REPLACE FUNCTION public.on_courier_status_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Kurye durumu değişmişse log kaydet
  IF OLD.has_own_courier IS DISTINCT FROM NEW.has_own_courier THEN
    -- Değişiklik logunu kaydet
    INSERT INTO public.courier_status_changes (
      shop_id,
      previous_status,
      new_status,
      admin_credit_at_change,
      commission_debt_at_change,
      cash_revenue_at_change,
      online_revenue_at_change,
      notes
    ) VALUES (
      NEW.id,
      OLD.has_own_courier,
      NEW.has_own_courier,
      OLD.admin_credit,
      OLD.commission_debt,
      OLD.cash_payment_revenue,
      OLD.online_payment_revenue,
      CASE
        WHEN NEW.has_own_courier THEN 'Kuryesiz → Kuryeli geçiş yapıldı'
        ELSE 'Kuryeli → Kuryesiz geçiş yapıldı'
      END
    );
    
    -- KURYELI → KURYESIZ geçişi
    IF OLD.has_own_courier = TRUE AND NEW.has_own_courier = FALSE THEN
      -- Komisyon borcu varsa, bu borcun ödenmesi gerekir
      -- Borç alacaktan düşülür (eğer yeterliyse)
      IF OLD.commission_debt > 0 AND OLD.admin_credit > 0 THEN
        -- Alacak borcun karşılayabilir
        IF OLD.admin_credit >= OLD.commission_debt THEN
          NEW.admin_credit := OLD.admin_credit - OLD.commission_debt;
          NEW.commission_debt := 0;
        ELSE
          -- Alacak yetmez, kalan borç kalır
          NEW.commission_debt := OLD.commission_debt - OLD.admin_credit;
          NEW.admin_credit := 0;
        END IF;
      END IF;
    END IF;
    
    -- KURYESIZ → KURYELI geçişi
    IF OLD.has_own_courier = FALSE AND NEW.has_own_courier = TRUE THEN
      -- Mevcut sistem zaten düzgün çalışır
      -- Alacaklar olduğu gibi kalır
      -- Yeni siparişler kuryeli sisteme göre hesaplanır
      NULL; -- Özel işlem gerekmez
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- 12. Kurye değişikliği trigger
DROP TRIGGER IF EXISTS on_courier_status_change ON public.shops;
CREATE TRIGGER on_courier_status_change
BEFORE UPDATE ON public.shops
FOR EACH ROW
EXECUTE FUNCTION public.on_courier_status_change();

-- 13. Kurye durumu değişikliği için RLS
ALTER TABLE public.courier_status_changes ENABLE ROW LEVEL SECURITY;

CREATE POLICY courier_status_changes_admin_full ON public.courier_status_changes
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = (SELECT auth.uid()) AND role = 'admin'
    )
  );

CREATE POLICY courier_status_changes_seller_read ON public.courier_status_changes
  FOR SELECT
  USING (
    shop_id IN (
      SELECT id FROM public.shops
      WHERE owner_id = (SELECT auth.uid())
    )
  );

-- Migration tamamlandı
-- Kontrol için query: SELECT tgname, tgenabled FROM pg_trigger WHERE tgrelid IN (SELECT oid FROM pg_class WHERE relname IN ('orders', 'payout_requests', 'shops'));

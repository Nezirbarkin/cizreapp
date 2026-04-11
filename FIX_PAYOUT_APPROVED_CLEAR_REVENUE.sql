-- ============================================================================
-- FIX: Ödeme İsteği Onaylandığında (approved) Kazançları Sıfırla
-- ============================================================================
-- Problem: approved durumunda sadece total_paid artıyor, kazançlar sıfırlanmıyor
-- İstek: approved durumunda hem total_paid eklensin hem kazançlar sıfırlansın
-- ============================================================================

-- Trigger fonksiyonunu güncelle
DROP TRIGGER IF EXISTS clear_shop_balance ON public.payout_requests CASCADE;
DROP FUNCTION IF EXISTS public.clear_shop_balance() CASCADE;

CREATE OR REPLACE FUNCTION public.clear_shop_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_shop_has_courier BOOLEAN;
  v_commission_debt NUMERIC;
  v_admin_credit NUMERIC;
  v_cash_payment_revenue NUMERIC;
  v_online_payment_revenue NUMERIC;
BEGIN
  -- APPROVED DURUMU: Toplam ödenene ekle VE TÜM BAKİYELERİ SIFIRLA
  IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status != 'approved') THEN
    -- Shop bilgilerini al
    SELECT 
      has_own_courier,
      commission_debt,
      admin_credit,
      cash_payment_revenue,
      online_payment_revenue
    INTO 
      v_shop_has_courier,
      v_commission_debt,
      v_admin_credit,
      v_cash_payment_revenue,
      v_online_payment_revenue
    FROM public.shops
    WHERE id = NEW.shop_id;

    -- TÜM BAKİYELERİ SIFIRLA VE TOPLAM ÖDENENE EKLE
    UPDATE public.shops
    SET 
      commission_debt = 0,              -- Komisyon borcu sıfırla
      admin_credit = 0,                 -- Admin'den alacak sıfırla
      cash_payment_revenue = 0,         -- Kapıda ödeme kazancı sıfırla
      online_payment_revenue = 0,       -- Online ödeme kazancı sıfırla
      total_collected_cash = 0,         -- Toplanan nakit sıfırla
      total_paid = total_paid + NEW.amount,  -- Toplam ödenene ekle
      paid_at = NOW(),                  -- Ödeme tarihi
      updated_at = NOW()
    WHERE id = NEW.shop_id;
    
    RAISE NOTICE 'PAYOUT APPROVED: Shop ID=% - TÜM BAKİYELER SIFIRLANDI', NEW.shop_id;
    RAISE NOTICE '  └─ Toplam Ödenen: +%', NEW.amount;
    RAISE NOTICE '  └─ Kapıda Kazanç: % → 0', v_cash_payment_revenue;
    RAISE NOTICE '  └─ Online Kazanç: % → 0', v_online_payment_revenue;
  END IF;

  -- PAID DURUMU: Artık bir şey yapmaya gerek yok (approved'da hallettik)
  IF NEW.status = 'paid' AND (OLD.status IS NULL OR OLD.status != 'paid') THEN
    RAISE NOTICE 'PAYOUT PAID: Shop ID=% - Zaten approved durumunda temizlendi', NEW.shop_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- Trigger'ı oluştur
CREATE TRIGGER clear_shop_balance
AFTER UPDATE ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.clear_shop_balance();

SELECT '✅ Ödeme onaylandığında (approved) kazançlar sıfırlanacak' as result;

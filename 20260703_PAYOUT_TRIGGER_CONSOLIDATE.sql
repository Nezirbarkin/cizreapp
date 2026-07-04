-- ============================================================================
-- MIGRATION: 20260703_PAYOUT_TRIGGER_CONSOLIDATE.sql
-- -----------------------------------------------------------------------------
-- SORUN:
--   payout_requests üzerindeki `clear_shop_balance` trigger'ının İKİ ÇAKIŞAN
--   sürümü vardı (20260308000001_payout_paid_status_clear_balance.sql ve
--   FIX_PAYOUT_APPROVED_CLEAR_REVENUE.sql). Hangisinin canlı olduğu son
--   çalıştırılana bağlıydı → approved/paid semantiği belirsizdi.
--   AYRICA admin_dashboard_screen._processPayoutRequest (approved) Dart tarafında
--   `total_paid += amount` yapıyor, trigger de UPDATE'te tekrar `total_paid +=
--   NEW.amount` yapıyordu → ÇİFT SAYIM.
--
-- ÇÖZÜM (tek yetkili kaynak = TRIGGER):
--   1) Dart tarafındaki shops güncellemesi KALDIRILDI (yalnızca payout_requests
--      status'unu değiştirir).
--   2) Tek canonical trigger: approved VEYA paid durumuna İLK geçişte bir kez
--      "settle" eder (idempotent). approved→paid ikinci kez settle etmez.
--      Settle = tüm kazanç/alacak/borç kolonlarını sıfırla + pending_payout'tan
--      düş + total_paid'e ekle + paid_at yaz.
--
-- NOT (kısmi ödeme): Bu tasarım tam ödeme (satıcı net alacağının tamamını çeker)
--   varsayımına dayanır — uygulamadaki diğer tüm akışlar (hızlı butonlar,
--   Alacak/Verecek Kapat) da tam-sıfırlama yapar. Kısmi ödeme senaryosu
--   gerekirse admin_credit/commission_debt için ayrıca düşüm mantığı eklenmeli.
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS clear_shop_balance ON public.payout_requests CASCADE;
DROP FUNCTION IF EXISTS public.clear_shop_balance() CASCADE;

CREATE OR REPLACE FUNCTION public.clear_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Tek settlement noktası: approved VEYA paid'e İLK geçiş.
  -- OLD zaten approved/paid ise (örn. approved -> paid) TEKRAR settle etmez.
  IF NEW.status IN ('approved', 'paid')
     AND (OLD.status IS NULL OR OLD.status NOT IN ('approved', 'paid')) THEN

    UPDATE public.shops
    SET
      commission_debt        = 0,   -- komisyon borcu
      admin_credit           = 0,   -- adminden alacak
      cash_payment_revenue   = 0,   -- kapıda kazanç (satıcı genel bakış kartı)
      online_payment_revenue = 0,   -- online kazanç (satıcı genel bakış kartı)
      total_collected_cash   = 0,   -- toplanan nakit
      pending_payout         = GREATEST(COALESCE(pending_payout, 0) - NEW.amount, 0),
      total_paid             = COALESCE(total_paid, 0) + NEW.amount,
      paid_at                = NOW(),
      updated_at             = NOW()
    WHERE id = NEW.shop_id;

    RAISE NOTICE 'PAYOUT SETTLED: shop=% amount=% (status % -> %)',
      NEW.shop_id, NEW.amount, OLD.status, NEW.status;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

CREATE TRIGGER clear_shop_balance
AFTER UPDATE ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.clear_shop_balance();

COMMENT ON FUNCTION public.clear_shop_balance() IS
'payout_requests approved/paid ilk geçişte shops bakiyelerini bir kez settle eder (idempotent). total_paid yalnızca burada artar; Dart tarafı artık dokunmaz (çift sayım önlendi). 2026-07-03 konsolidasyon.';

-- Doğrulama
DO $$
DECLARE v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'clear_shop_balance' AND NOT tgisinternal;
  IF v_count = 1 THEN
    RAISE NOTICE 'BASARILI: tek clear_shop_balance trigger aktif';
  ELSE
    RAISE EXCEPTION 'HATA: beklenen 1 trigger, bulunan %', v_count;
  END IF;
END $$;

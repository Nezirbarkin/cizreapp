-- ============================================================================
-- Ödeme Sistemi İyileştirmesi
-- ============================================================================
-- 1) Satıcı ödeme isteği oluştururken onay mekanizması (dialog zaten var)
-- 2) Admin ödeme yapıldığında (paid durumu) tüm bakiyeleri sıfırla
-- 3) Hem kuryesi olan hem olmayan satıcılar için geçerli
-- ============================================================================

-- Önce mevcut trigger'ı güncelliyoruz
DROP TRIGGER IF EXISTS clear_shop_balance ON public.payout_requests CASCADE;
DROP FUNCTION IF EXISTS public.clear_shop_balance() CASCADE;

-- ============================================================================
-- YENİ CLEAR SHOP BALANCE FUNCTION
-- ============================================================================
-- Ödeme durumu değiştiğinde bakiyeleri güncelle
-- - approved: Bakiyeler tutulur (ödeme hazırlığı)
-- - paid: TÜM bakiyeler sıfırlanır (ödeme yapıldı)
CREATE OR REPLACE FUNCTION public.clear_shop_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_shop_has_courier BOOLEAN;
  v_commission_debt NUMERIC;
  v_admin_credit NUMERIC;
  v_cash_payment_revenue NUMERIC;
  v_online_payment_revenue NUMERIC;
BEGIN
  -- APPROVED DURUMU: Eski mantık (bakiyeler kısmi temizlenir)
  IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status != 'approved') THEN
    -- Shop bilgilerini al
    SELECT 
      has_own_courier, 
      commission_debt, 
      admin_credit
    INTO 
      v_shop_has_courier, 
      v_commission_debt, 
      v_admin_credit
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
      
      RAISE NOTICE 'PAYOUT APPROVED (Kuryeli): Shop ID=%, Borç=% → 0, Alacak=% → 0, Ödenen=%', 
        NEW.shop_id, v_commission_debt, v_admin_credit, NEW.amount;
    ELSE
      -- Kuryesi olmayan: Sadece alacağı düş
      UPDATE public.shops
      SET 
        admin_credit = GREATEST(admin_credit - NEW.amount, 0),
        total_paid = total_paid + NEW.amount,
        updated_at = NOW()
      WHERE id = NEW.shop_id;
      
      RAISE NOTICE 'PAYOUT APPROVED (Kuryesiz): Shop ID=%, Alacak=% → %, Ödenen=%', 
        NEW.shop_id, v_admin_credit, GREATEST(v_admin_credit - NEW.amount, 0), NEW.amount;
    END IF;
  END IF;

  -- PAID DURUMU: YENİ MANTIK - TÜM BAKİYELERİ SIFIRLA
  -- Admin ödemeyi yaptı, artık tüm hesaplar temizlenmeli
  IF NEW.status = 'paid' AND (OLD.status IS NULL OR OLD.status != 'paid') THEN
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

    -- TÜM BAKİYELERİ SIFIRLA (hem kuryeli hem kuryesiz için)
    UPDATE public.shops
    SET 
      commission_debt = 0,              -- Komisyon borcu sıfırla
      admin_credit = 0,                 -- Admin'den alacak sıfırla
      cash_payment_revenue = 0,         -- Kapıda ödeme kazancı sıfırla
      online_payment_revenue = 0,       -- Online ödeme kazancı sıfırla
      total_collected_cash = 0,         -- Toplanan nakit sıfırla
      paid_at = NOW(),                  -- Ödeme tarihi
      updated_at = NOW()
    WHERE id = NEW.shop_id;
    
    RAISE NOTICE 'PAYOUT PAID: Shop ID=% - TÜM BAKİYELER SIFIRLANDI', NEW.shop_id;
    RAISE NOTICE '  └─ Komisyon Borcu: % → 0', v_commission_debt;
    RAISE NOTICE '  └─ Admin Alacak: % → 0', v_admin_credit;
    RAISE NOTICE '  └─ Kapıda Kazanç: % → 0', v_cash_payment_revenue;
    RAISE NOTICE '  └─ Online Kazanç: % → 0', v_online_payment_revenue;
    RAISE NOTICE '  └─ Kurye Tipi: %', CASE WHEN v_shop_has_courier THEN 'Kuryeli' ELSE 'Kuryesiz' END;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- Trigger'ı yeniden oluştur
CREATE TRIGGER clear_shop_balance
AFTER UPDATE ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.clear_shop_balance();

-- ============================================================================
-- NOTIFICATION TYPE GÜNCELLEME
-- ============================================================================
-- Eğer 'payout_paid' bildirim tipi yoksa ekle
DO $$
BEGIN
  -- notifications tablosundaki type constraint'i güncelle
  ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
  
  ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'like', 'comment', 'follow', 'mention', 'order', 'shop', 
    'support_response', 'support_status', 'complaint_response', 
    'report', 'payout_approved', 'payout_rejected', 'payout_paid',
    'verification_code', 'post_share', 'story_like', 'follow_request',
    'follow_request_accepted'
  ));
  
  RAISE NOTICE 'Bildirim tipi "payout_paid" eklendi';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Bildirim tipi güncellenemedi: %', SQLERRM;
END $$;

-- ============================================================================
-- ADMIN BİLDİRİM TETİKLEYİCİSİ (ÖDEME İSTEĞİ OLUŞTURULDUĞUNDA)
-- ============================================================================
-- Satıcı ödeme isteği oluşturduğunda admin'e bildirim gönder
CREATE OR REPLACE FUNCTION public.notify_admin_on_payout_request()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_id UUID;
  v_shop_name TEXT;
BEGIN
  -- Sadece yeni ödeme istekleri için çalış
  IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
    -- Admin kullanıcısını bul
    SELECT id INTO v_admin_id
    FROM public.profiles
    WHERE role = 'admin'
    LIMIT 1;
    
    -- Shop adını al
    SELECT name INTO v_shop_name
    FROM public.shops
    WHERE id = NEW.shop_id;
    
    -- Admin'e bildirim gönder
    IF v_admin_id IS NOT NULL THEN
      INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content,
        is_read,
        created_at
      ) VALUES (
        v_admin_id,
        'shop',
        'Yeni Ödeme İsteği',
        v_shop_name || ' mağazasından ₺' || NEW.amount::TEXT || ' tutarında ödeme isteği geldi.',
        false,
        NOW()
      );
      
      RAISE NOTICE 'Admin''e yeni ödeme isteği bildirimi gönderildi';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = 'public';

-- Trigger oluştur (eğer yoksa)
DROP TRIGGER IF EXISTS notify_admin_on_payout_request ON public.payout_requests;
CREATE TRIGGER notify_admin_on_payout_request
AFTER INSERT ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.notify_admin_on_payout_request();

-- ============================================================================
-- YORUM VE AÇIKLAMALAR
-- ============================================================================
COMMENT ON FUNCTION public.clear_shop_balance() IS 
'Ödeme durumu değiştiğinde shop bakiyelerini günceller.
- approved: Eski mantık (kısmi temizlik)
- paid: YENİ - TÜM bakiyeler sıfırlanır (hem kuryeli hem kuryesiz)';

COMMENT ON FUNCTION public.notify_admin_on_payout_request() IS
'Satıcı ödeme isteği oluşturduğunda admin''e bildirim gönderir';

-- ============================================================================
-- KONTROL SORGUSU
-- ============================================================================
-- Bu sorguyu çalıştırarak trigger'ların aktif olduğunu doğrulayabilirsiniz:
-- SELECT 
--   t.tgname as trigger_name,
--   c.relname as table_name,
--   p.proname as function_name,
--   CASE t.tgenabled 
--     WHEN 'O' THEN 'enabled'
--     WHEN 'D' THEN 'disabled'
--     ELSE 'unknown'
--   END as status
-- FROM pg_trigger t
-- JOIN pg_class c ON t.tgrelid = c.oid
-- JOIN pg_proc p ON t.tgfoid = p.oid
-- WHERE c.relname = 'payout_requests'
--   AND NOT t.tgisinternal
-- ORDER BY t.tgname;

-- ============================================================================
-- MİGRASYON TAMAMLANDI
-- ============================================================================
DO $$
BEGIN
  RAISE NOTICE '✅ Ödeme sistemi iyileştirmesi tamamlandı';
  RAISE NOTICE '  1. Satıcı ödeme isteği oluştururken onay mekanizması aktif (UI tarafında)';
  RAISE NOTICE '  2. Admin ödeme yaptığında (paid) TÜM bakiyeler sıfırlanıyor';
  RAISE NOTICE '  3. Hem kuryeli hem kuryesiz satıcılar için geçerli';
  RAISE NOTICE '  4. Admin''e yeni ödeme isteği bildirimi gönderiliyor';
END $$;

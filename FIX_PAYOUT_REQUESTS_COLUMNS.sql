-- ============================================================================
-- PAYOUT_REQUESTS TABLO DÜZELTME VE ÖDEME İSTEĞİ SİSTEMİ
-- ============================================================================
-- Sorun: payout_requests tablosunda amount, admin_credit, commission_debt sütunları yok
-- Sorun: notifications INSERT RLS hatası veriyor
-- Çözüm: Eksik sütunları ekle, trigger'ları düzelt, notifications policy garanti et

-- 0. Notifications INSERT Policy'yi garanti et (önce)
DROP POLICY IF EXISTS "notifications_insert" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;
CREATE POLICY "notifications_insert_policy" ON public.notifications
    FOR INSERT
    TO authenticated
    WITH CHECK (true); -- Trigger'lar SECURITY DEFINER olduğu için her INSERT'e izin ver

-- 1. payout_requests tablosuna eksik sütunları ekle
ALTER TABLE public.payout_requests
  ADD COLUMN IF NOT EXISTS amount DECIMAL(12, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS admin_credit DECIMAL(12, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commission_debt DECIMAL(12, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS net_receivable DECIMAL(12, 2) DEFAULT 0;

-- 2. Yorumlar ekle
COMMENT ON COLUMN public.payout_requests.amount IS 'Net ödenecek tutar (kullanıcıya gösterilecek)';
COMMENT ON COLUMN public.payout_requests.admin_credit IS 'Satıcının online ödemelerden alacağı (ödeme isteği sırasında)';
COMMENT ON COLUMN public.payout_requests.commission_debt IS 'Satıcının kapıda ödemelerden komisyon borcu (ödeme isteği sırasında)';
COMMENT ON COLUMN public.payout_requests.net_receivable IS 'Net alacak (admin_credit - commission_debt veya direkt admin_credit)';

-- 3. validate_payout_request trigger'ını düzelt
DROP TRIGGER IF EXISTS validate_payout_request ON public.payout_requests CASCADE;
DROP FUNCTION IF EXISTS public.validate_payout_request() CASCADE;

CREATE OR REPLACE FUNCTION public.validate_payout_request()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_credit DECIMAL;
  v_commission_debt DECIMAL;
  v_net_receivable DECIMAL;
  v_has_own_courier BOOLEAN;
BEGIN
  -- Satıcının durumunu al
  SELECT admin_credit, commission_debt, has_own_courier
  INTO v_admin_credit, v_commission_debt, v_has_own_courier
  FROM public.shops
  WHERE id = NEW.shop_id;

  -- Kuryesi olmayan satıcılar direkt alacağını alır
  IF NOT v_has_own_courier THEN
    NEW.admin_credit := v_admin_credit;
    NEW.commission_debt := 0;
    NEW.net_receivable := v_admin_credit;
    NEW.amount := v_admin_credit;
  -- Kuryesi olan satıcılar: Alacak - Borç
  ELSE
    v_net_receivable := v_admin_credit - v_commission_debt;
    
    IF v_net_receivable <= 0 THEN
      RAISE EXCEPTION 'Ödeme isteği oluşturulamaz. Komisyon borcunuz: ₺%. Online ödeme alacağınız: ₺%', 
        v_commission_debt, v_admin_credit;
    END IF;

    NEW.admin_credit := v_admin_credit;
    NEW.commission_debt := v_commission_debt;
    NEW.net_receivable := v_net_receivable;
    NEW.amount := v_net_receivable;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

CREATE TRIGGER validate_payout_request
BEFORE INSERT ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.validate_payout_request();

-- 4. Shops tablosuna "şimdiye kadar ödenen" sütunu ekle
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS total_paid_amount DECIMAL(12, 2) DEFAULT 0;

COMMENT ON COLUMN public.shops.total_paid_amount IS 'Şimdiye kadar satıcıya ödenen toplam tutar';

-- 6. clear_shop_balance trigger'ını güncelle - ödenen tutarı da ekle
DROP TRIGGER IF EXISTS clear_shop_balance ON public.payout_requests CASCADE;
DROP FUNCTION IF EXISTS public.clear_shop_balance() CASCADE;

CREATE OR REPLACE FUNCTION public.clear_shop_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Admin onayladığında (status = 'approved' veya 'paid') shop balance sıfırlansın
  IF NEW.status IN ('approved', 'paid') AND OLD.status NOT IN ('approved', 'paid') THEN
    -- Önce total_paid_amount'ı artır
    UPDATE public.shops
    SET
      total_paid_amount = total_paid_amount + NEW.amount,
      commission_debt = 0,
      admin_credit = 0,
      updated_at = NOW()
    WHERE id = NEW.shop_id;
    
    RAISE NOTICE 'Shop % balance sıfırlandı, ödenen tutar eklendi. Amount: %',
      NEW.shop_id, NEW.amount;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

CREATE TRIGGER clear_shop_balance
AFTER UPDATE ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.clear_shop_balance();

-- 7. Mevcut bekleyen payout_requests'leri güncelle
UPDATE public.payout_requests pr
SET
  admin_credit = s.admin_credit,
  commission_debt = s.commission_debt,
  net_receivable = CASE
    WHEN s.has_own_courier THEN s.admin_credit - s.commission_debt
    ELSE s.admin_credit
  END
FROM public.shops s
WHERE pr.shop_id = s.id
  AND pr.status = 'pending'
  AND pr.admin_credit IS NULL;

-- 6. Ödeme isteği için admin bildirimi trigger'ı
DROP TRIGGER IF EXISTS notify_admin_payout_request ON public.payout_requests CASCADE;
DROP FUNCTION IF EXISTS public.notify_admin_payout_request() CASCADE;

CREATE OR REPLACE FUNCTION public.notify_admin_payout_request()
RETURNS TRIGGER AS $$
DECLARE
  v_shop_name TEXT;
  v_seller_info JSONB;
  v_admin_id UUID;
BEGIN
  -- Sadece yeni ödeme isteğinde bildirim gönder
  IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
    -- Shop ve Seller bilgilerini al
    SELECT s.name, jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'full_name', COALESCE(p.full_name, p.username),
      'avatar_url', p.avatar_url
    )
    INTO v_shop_name, v_seller_info
    FROM public.shops s
    JOIN public.profiles p ON p.id = s.owner_id
    WHERE s.id = NEW.shop_id;

    -- Admin kullanıcı ID'sini al (is_admin = true olan ilk kullanıcı)
    SELECT id INTO v_admin_id
    FROM public.profiles
    WHERE is_admin = true
    LIMIT 1;

    -- Admin yoksa notification gönderme
    IF v_admin_id IS NULL THEN
      RAISE NOTICE 'Admin kullanıcı bulunamadı, bildirim gönderilemedi';
      RETURN NEW;
    END IF;

    -- Admin'e notification gönder
    INSERT INTO public.notifications (
      user_id,
      type,
      title,
      content,
      actor_id,
      actor_name,
      actor_avatar,
      entity_id,
      is_read,
      created_at
    ) VALUES (
      v_admin_id,
      'payout_request',
      'Yeni ödeme isteği',
      v_shop_name || ' mağazası ₺' || NEW.amount || ' tutarında ödeme isteği oluşturdu',
      (v_seller_info->>'id')::UUID,
      v_seller_info->>'full_name',
      v_seller_info->>'avatar_url',
      NEW.id,
      false,
      NOW()
    );

    RAISE NOTICE 'Admin''e ödeme isteği bildirimi gönderildi';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

CREATE TRIGGER notify_admin_payout_request
AFTER INSERT ON public.payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.notify_admin_payout_request();

-- 7. Kontrol sorguları
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'PAYOUT_REQUESTS TABLO DÜZELTME TAMAMLANDI!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Eksik sütunlar eklendi: amount, admin_credit, commission_debt, net_receivable';
    RAISE NOTICE 'Trigger güncellendi: validate_payout_request, clear_shop_balance';
    RAISE NOTICE 'Admin onay sonrası shop balance otomatik sıfırlanacak';
    RAISE NOTICE '================================================================';
END $$;

-- Sonuçları göster
SELECT
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'payout_requests'
  AND column_name IN ('amount', 'admin_credit', 'commission_debt', 'net_receivable')
ORDER BY ordinal_position;

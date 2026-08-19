-- =============================================================================
-- İlan kategorilerine ücretli/ücretsiz yayınlama desteği
-- =============================================================================
-- İSTEK: Bazı ilan kategorileri (örn. "Kayıp") ücretsiz kalsın, admin diğer
-- kategoriler için TL cinsinden bir yayınlama ücreti tanımlayabilsin.
--
-- TASARIM KARARLARI (kullanıcı onayıyla):
--   1) Ücret, ilan GÖNDERİLDİĞİ anda hemen tahsil edilir (onay bekleyip
--      beklemediğinden bağımsız — onay ayarı zaten varsayılan kapalı).
--   2) Admin ilanı REDDEDERSE ücret otomatik iade edilir. Kullanıcı kendi
--      ilanını silerse iade YOK (yayın hakkını kullanmış sayılır);
--      arşivleme de iade tetiklemez.
--
-- Mevcut bakiye altyapısı (user_balances/balance_transactions, İyzico ile
-- yüklenen gerçek TL bakiyesi) yeniden kullanılıyor — yeni bir cüzdan/ödeme
-- sistemi icat edilmiyor. deduct_from_balance/add_to_balance RPC'leri
-- BİLEREK çağrılmıyor: 20260727000008_harden_balance_rpc_permissions.sql ile
-- deduct_from_balance yalnız 'courier_payment' tipiyle sınırlandı ve
-- add_to_balance'ın 'refund' özel durumu yalnız o literal tip için çalışıyor
-- (20260709000005_BALANCE_REFUND_FIX.sql). Bu yüzden validate_ilan_write()
-- trigger'ı (zaten SECURITY DEFINER) aynı muhasebe desenini (total_spent /
-- total_refunds) kendi 'ilan_publish_fee' / 'ilan_publish_refund' tipleriyle
-- doğrudan uyguluyor.
-- =============================================================================

BEGIN;

ALTER TABLE public.ilan_categories
  ADD COLUMN IF NOT EXISTS publish_fee numeric(10,2) NOT NULL DEFAULT 0
    CHECK (publish_fee >= 0);

COMMENT ON COLUMN public.ilan_categories.publish_fee IS
  'İlan yayınlama ücreti (TL). 0 = ücretsiz. İlan gönderilirken kullanıcının bakiyesinden düşülür.';

ALTER TABLE public.ilanlar
  ADD COLUMN IF NOT EXISTS paid_fee numeric(10,2) NOT NULL DEFAULT 0
    CHECK (paid_fee >= 0);
ALTER TABLE public.ilanlar
  ADD COLUMN IF NOT EXISTS fee_refunded boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.ilanlar.paid_fee IS
  'Bu ilan gönderilirken fiilen tahsil edilen ücret (kategori ücreti sonradan değişse bile sabit kalır).';
COMMENT ON COLUMN public.ilanlar.fee_refunded IS
  'Ücret admin reddi nedeniyle iade edildiyse true — tekrar iade edilmesini engeller.';

CREATE OR REPLACE FUNCTION public.validate_ilan_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_settings public.ilan_settings%ROWTYPE;
  v_pricing_mode text;
  v_allowed_conditions text[];
  v_publish_fee numeric(10,2);
  v_is_admin boolean := public.ilan_is_admin();
  v_active_count integer;
  v_balance_id uuid;
  v_current_balance numeric(12,2);
BEGIN
  SELECT * INTO v_settings FROM public.ilan_settings WHERE id = 1;

  IF NOT v_is_admin THEN
    IF NOT v_settings.is_enabled THEN
      RAISE EXCEPTION 'İlan sistemi şu anda kapalı' USING ERRCODE = 'P0001';
    END IF;
    IF TG_OP = 'INSERT' AND NOT v_settings.allow_user_create THEN
      RAISE EXCEPTION 'Kullanıcı ilan paylaşımı şu anda kapalı' USING ERRCODE = '42501';
    END IF;
    IF NEW.owner_id IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'Başka bir kullanıcı adına ilan oluşturulamaz' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT c.pricing_mode, c.allowed_conditions, c.publish_fee
    INTO v_pricing_mode, v_allowed_conditions, v_publish_fee
  FROM public.ilan_categories c
  WHERE c.id = NEW.category_id
    AND (c.is_active OR v_is_admin);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Geçersiz veya pasif ilan kategorisi' USING ERRCODE = '23514';
  END IF;

  IF v_pricing_mode = 'forbidden' THEN
    NEW.price := NULL;
    NEW.currency := NULL;
    NEW.is_negotiable := false;
  ELSIF v_pricing_mode = 'required' AND (NEW.price IS NULL OR NEW.price <= 0) THEN
    RAISE EXCEPTION 'Bu kategori için sıfırdan büyük fiyat zorunludur' USING ERRCODE = '23514';
  ELSIF NEW.price IS NOT NULL THEN
    NEW.currency := COALESCE(NEW.currency, 'TRY');
  ELSE
    NEW.currency := NULL;
    NEW.is_negotiable := false;
  END IF;

  IF cardinality(v_allowed_conditions) > 0
     AND (NEW.item_condition IS NULL OR NOT (NEW.item_condition = ANY(v_allowed_conditions))) THEN
    RAISE EXCEPTION 'Bu kategori için geçersiz ürün durumu' USING ERRCODE = '23514';
  END IF;

  NEW.title := btrim(NEW.title);
  NEW.description := btrim(NEW.description);
  NEW.updated_at := now();

  IF TG_OP = 'INSERT' THEN
    IF NOT v_is_admin THEN
      SELECT count(*) INTO v_active_count
      FROM public.ilanlar i
      WHERE i.owner_id = NEW.owner_id
        AND i.status IN ('draft', 'pending', 'published');
      IF v_active_count >= v_settings.max_active_per_user THEN
        RAISE EXCEPTION 'Aktif ilan limitine ulaştınız' USING ERRCODE = 'P0001';
      END IF;
      NEW.status := CASE WHEN v_settings.require_approval THEN 'pending' ELSE 'published' END;

      -- Kategori yayınlama ücreti: onay durumundan bağımsız olarak ilan
      -- gönderilirken hemen tahsil edilir. Reddedilirse aşağıdaki UPDATE
      -- dalında otomatik iade edilir.
      IF v_publish_fee > 0 THEN
        SELECT ub.id, ub.balance INTO v_balance_id, v_current_balance
        FROM public.user_balances ub
        WHERE ub.user_id = NEW.owner_id
        FOR UPDATE;

        IF v_balance_id IS NULL OR v_current_balance < v_publish_fee THEN
          RAISE EXCEPTION 'Yetersiz bakiye: bu kategoride ilan yayınlamak % TL ücretlidir',
            v_publish_fee
            USING ERRCODE = 'P0001';
        END IF;

        UPDATE public.user_balances
        SET balance = v_current_balance - v_publish_fee,
            total_spent = total_spent + v_publish_fee,
            updated_at = now()
        WHERE id = v_balance_id;

        INSERT INTO public.balance_transactions (
          user_id, type, amount, net_amount, balance_before, balance_after,
          reference_type, reference_id, status, description
        ) VALUES (
          NEW.owner_id, 'ilan_publish_fee'::public.balance_transaction_type,
          v_publish_fee, v_publish_fee,
          v_current_balance, v_current_balance - v_publish_fee,
          'ilan', NEW.id, 'completed',
          format('İlan yayınlama ücreti: %s', left(NEW.title, 120))
        );

        NEW.paid_fee := v_publish_fee;
      END IF;
    END IF;
    IF NEW.status = 'published' THEN
      NEW.published_at := COALESCE(NEW.published_at, now());
      NEW.expires_at := COALESCE(NEW.expires_at, now() + make_interval(days => v_settings.default_expiry_days));
    END IF;
  ELSE
    IF NOT v_is_admin THEN
      NEW.moderated_by := OLD.moderated_by;
      NEW.moderated_at := OLD.moderated_at;
      NEW.rejection_reason := OLD.rejection_reason;
      NEW.paid_fee := OLD.paid_fee;
      NEW.fee_refunded := OLD.fee_refunded;
      -- Kullanıcı içerik/kategori/fiyat değiştirdiyse tekrar moderasyona gönder.
      IF ROW(NEW.category_id, NEW.title, NEW.description, NEW.price, NEW.attributes)
         IS DISTINCT FROM ROW(OLD.category_id, OLD.title, OLD.description, OLD.price, OLD.attributes) THEN
        NEW.status := CASE WHEN v_settings.require_approval THEN 'pending' ELSE 'published' END;
      ELSIF NEW.status NOT IN ('sold', 'rented', 'found', 'archived', OLD.status) THEN
        NEW.status := OLD.status;
      END IF;
    END IF;
    IF NEW.status = 'published' AND OLD.status IS DISTINCT FROM 'published' THEN
      NEW.published_at := now();
      NEW.expires_at := COALESCE(NEW.expires_at, now() + make_interval(days => v_settings.default_expiry_days));
      IF v_is_admin THEN
        NEW.moderated_by := (SELECT auth.uid());
        NEW.moderated_at := now();
      END IF;
    ELSIF v_is_admin AND NEW.status IN ('rejected', 'archived') AND NEW.status IS DISTINCT FROM OLD.status THEN
      NEW.moderated_by := (SELECT auth.uid());
      NEW.moderated_at := now();

      -- Admin reddederse ve daha önce ücret tahsil edildiyse otomatik iade et.
      -- (archived tetiklemez — sadece açık bir "reddet" kararı iade doğurur.)
      IF NEW.status = 'rejected' AND OLD.paid_fee > 0 AND NOT COALESCE(OLD.fee_refunded, false) THEN
        SELECT ub.id, ub.balance INTO v_balance_id, v_current_balance
        FROM public.user_balances ub
        WHERE ub.user_id = OLD.owner_id
        FOR UPDATE;

        IF v_balance_id IS NOT NULL THEN
          UPDATE public.user_balances
          SET balance = v_current_balance + OLD.paid_fee,
              total_refunds = total_refunds + OLD.paid_fee,
              updated_at = now()
          WHERE id = v_balance_id;

          INSERT INTO public.balance_transactions (
            user_id, type, amount, net_amount, balance_before, balance_after,
            reference_type, reference_id, status, description
          ) VALUES (
            OLD.owner_id, 'ilan_publish_refund'::public.balance_transaction_type,
            OLD.paid_fee, OLD.paid_fee,
            v_current_balance, v_current_balance + OLD.paid_fee,
            'ilan', OLD.id, 'completed',
            format('İlan reddedildi, yayınlama ücreti iade edildi: %s', left(OLD.title, 120))
          );
        END IF;

        NEW.fee_refunded := true;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;

-- =============================================================================
-- DOĞRULAMA:
--   -- Bir kategoriye ücret tanımla:
--   UPDATE public.ilan_categories SET publish_fee = 25 WHERE slug = 'satilik';
--
--   -- Yetersiz bakiyeli bir kullanıcı o kategoride ilan denerse INSERT
--   -- "Yetersiz bakiye: ..." hatasıyla reddedilmeli.
--
--   -- Yeterli bakiyeli kullanıcı ilan oluşturunca:
--   SELECT paid_fee FROM public.ilanlar WHERE id = '<yeni-ilan-id>'; -- 25
--   SELECT * FROM public.balance_transactions
--     WHERE reference_type = 'ilan' AND reference_id = '<yeni-ilan-id>'
--     ORDER BY created_at DESC LIMIT 1; -- type = ilan_publish_fee
--
--   -- Admin reddedince:
--   SELECT fee_refunded FROM public.ilanlar WHERE id = '<yeni-ilan-id>'; -- true
--   SELECT * FROM public.balance_transactions
--     WHERE reference_type = 'ilan' AND reference_id = '<yeni-ilan-id>'
--     AND type = 'ilan_publish_refund'; -- 1 satır
-- =============================================================================

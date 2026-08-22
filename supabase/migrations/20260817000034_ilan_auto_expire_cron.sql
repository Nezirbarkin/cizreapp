-- ============================================================================
-- İlan süresi dolunca otomatik "expired" statüsüne geçiş (2026-08-16)
-- ----------------------------------------------------------------------------
-- İSTEK: İlanlar admin tarafından belirlenen süre (ilan_settings.
-- default_expiry_days) dolunca kalan gün UI'da gösterilsin ve otomatik
-- arşivlensin. expires_at kolonu ve public read filtresi zaten vardı, ama
-- hiçbir job satırı fiilen 'expired' statüsüne taşımıyordu — süresi geçen
-- ilanlar sadece görünmez oluyordu, "İlanlarım > Arşiv" sekmesine düşmüyordu.
--
-- ÖNEMLİ: validate_ilan_write() BEFORE UPDATE trigger'ı (son hali
-- 20260817000025_ilan_category_publish_fee.sql), admin olmayan bir aktörün
-- status'u ('sold','rented','found','archived',OLD.status) dışına
-- çıkarmasını OLD.status'e geri döndürüyor. Cron job kimliksiz (auth.uid()
-- NULL) çalıştığından ilan_is_admin() false döner ve düz bir
-- "UPDATE ... SET status='expired'" bu trigger tarafından sessizce geri
-- alınırdı. Bu yüzden fonksiyonu, aynı izin listesine 'expired' eklenmiş
-- haliyle CREATE OR REPLACE ediyoruz (owner'ın zaten kendi ilanını
-- 'archived' yapabildiği desenle tutarlı).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

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
      ELSIF NEW.status NOT IN ('sold', 'rented', 'found', 'archived', 'expired', OLD.status) THEN
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

-- Süresi geçen yayındaki ilanları 'expired' statüsüne taşır.
-- SECURITY DEFINER + table owner olarak çalıştığından RLS'i bypass eder.
CREATE OR REPLACE FUNCTION public.expire_stale_ilanlar()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.ilanlar
  SET status = 'expired'
  WHERE status = 'published'
    AND expires_at IS NOT NULL
    AND expires_at <= now();
$$;

COMMENT ON FUNCTION public.expire_stale_ilanlar() IS
  'expires_at süresi geçmiş yayındaki ilanları expired statüsüne taşır; saatlik pg_cron job tarafından çağrılır.';

DO $$
BEGIN
  -- Eski job varsa kaldır (idempotent).
  PERFORM cron.unschedule('expire-stale-ilanlar-hourly')
  WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'expire-stale-ilanlar-hourly'
  );

  PERFORM cron.schedule(
    'expire-stale-ilanlar-hourly',
    '0 * * * *',
    $cron$ SELECT public.expire_stale_ilanlar(); $cron$
  );
END;
$$;

SELECT jobname, schedule, active
FROM cron.job
WHERE jobname = 'expire-stale-ilanlar-hourly';

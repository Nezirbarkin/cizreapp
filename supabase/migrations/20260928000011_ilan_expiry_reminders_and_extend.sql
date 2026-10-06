-- =============================================================================
-- Görev 3.9 — İlan süresi yönetimi: hatırlatma push'u + süreyi uzatma
-- =============================================================================
-- Canlıda bulunan hata: saatlik `expire-stale-ilanlar-hourly` işi HER ÇALIŞMADA
-- düşüyordu: validate_ilan_write tetikleyicisi oturumsuz (cron) güncellemeyi
-- "Başka bir kullanıcı adına ilan oluşturulamaz" diye reddediyordu. Sonuç:
-- 13 ilanın 10'unun süresi 8–25 gün önce dolmuş ama durumları hâlâ
-- 'published' (herkese açık listelerde zaten görünmüyorlardı — okuma
-- politikası expires_at'e bakıyor — ama sahibi "Yayında" görüyordu ve
-- "Süresi doldu" hiçbir yerde yoktu).
--
-- Bu göç:
--   1) validate_ilan_write: YALNIZ sistem yazmaları (bu göçteki DEFINER
--      fonksiyonların işlem-içi `cizre.ilan_system_write` işareti) kullanıcı
--      doğrulamasını atlar. İstemci bu işareti kuramaz (PostgREST yalnız
--      public şemadaki fonksiyonları açar; set_config dışarıda).
--   2) expire_stale_ilanlar (aynı cron işi): süresi 3 gün / 1 gün içinde
--      dolacak ilanın sahibine hatırlatma, dolanı 'expired' yapıp "süresi doldu"
--      bildirimi. Her aşama ilan × süre başına BİR kez (ilan_expiry_notices).
--   3) extend_my_ilan(ilan): sahibi, süresi dolmuş ilanı yeniden yayınlar ya da
--      bitimine 7 günden az kalanı uzatır (varsayılan süre kadar). Etkin ilan
--      sınırı ve (varsa) kategori yayın ücreti yeni yayında olduğu gibi uygulanır.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Doğrulayıcı: sistem yazması işareti (gövdenin geri kalanı canlıdakiyle aynı)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_ilan_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- Görev 3.9: süre bitirme işi (cron, oturumsuz) ve süre uzatma RPC'si
  -- yalnız durum/süre alanlarını yazar; kullanıcı doğrulaması atlanır.
  IF TG_OP = 'UPDATE' AND current_setting('cizre.ilan_system_write', true) = 'on' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

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
$function$;

-- -----------------------------------------------------------------------------
-- 2) Hatırlatma günlüğü: ilan × aşama × o anki bitiş zamanı başına BİR bildirim
--    (süre uzatılınca yeni bitiş için hatırlatmalar yeniden çalışır)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ilan_expiry_notices (
  ilan_id uuid NOT NULL REFERENCES public.ilanlar(id) ON DELETE CASCADE,
  stage text NOT NULL CHECK (stage IN ('3d', '1d', 'expired')),
  expires_at timestamptz NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ilan_id, stage, expires_at)
);
ALTER TABLE public.ilan_expiry_notices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ilan_expiry_notices FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.ilan_expiry_notify(
  p_ilan public.ilanlar,
  p_stage text
)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v_title text := left(COALESCE(NULLIF(btrim(p_ilan.title), ''), 'İlanın'), 80);
  v_heading text;
  v_body text;
BEGIN
  INSERT INTO public.ilan_expiry_notices (ilan_id, stage, expires_at)
  VALUES (p_ilan.id, p_stage, p_ilan.expires_at)
  ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN
    RETURN;  -- bu aşama bu süre için zaten gönderildi
  END IF;

  IF p_stage = 'expired' THEN
    v_heading := 'İlanının süresi doldu';
    v_body := format('"%s" yayından kalktı. Tek dokunuşla süresini uzatabilirsin.', v_title);
  ELSIF p_stage = '1d' THEN
    v_heading := 'İlanının süresi yarın doluyor';
    v_body := format('"%s" 24 saat içinde yayından kalkacak. Uzatmak için dokun.', v_title);
  ELSE
    v_heading := 'İlanının süresi 3 gün içinde doluyor';
    v_body := format('"%s" yakında yayından kalkacak. Uzatmak için dokun.', v_title);
  END IF;

  INSERT INTO public.notifications (user_id, type, title, content, entity_type, entity_id, data, is_read, created_at)
  VALUES (
    p_ilan.owner_id,
    CASE WHEN p_stage = 'expired' THEN 'ilan_expired' ELSE 'ilan_expiring' END,
    v_heading,
    v_body,
    'ilan',
    p_ilan.id::text,
    jsonb_build_object('ilan_id', p_ilan.id, 'stage', p_stage, 'expires_at', p_ilan.expires_at),
    false,
    now()
  );
END;
$fn$;

REVOKE ALL ON FUNCTION private.ilan_expiry_notify(public.ilanlar, text) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 3) Saatlik iş (aynı cron: expire-stale-ilanlar-hourly): hatırlat + bitir
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_stale_ilanlar()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v public.ilanlar%ROWTYPE;
BEGIN
  -- Yaklaşan bitişler: 24 saatten az kaldıysa '1d', 3 günden az kaldıysa '3d'.
  FOR v IN
    SELECT * FROM public.ilanlar i
     WHERE i.status = 'published'
       AND i.expires_at > now()
       AND i.expires_at <= now() + interval '3 days'
  LOOP
    IF v.expires_at <= now() + interval '1 day' THEN
      PERFORM private.ilan_expiry_notify(v, '1d');
    ELSE
      PERFORM private.ilan_expiry_notify(v, '3d');
    END IF;
  END LOOP;

  -- Süresi dolanlar: durum 'expired' + bildirim (sistem yazması).
  PERFORM set_config('cizre.ilan_system_write', 'on', true);
  FOR v IN
    UPDATE public.ilanlar i
       SET status = 'expired'
     WHERE i.status = 'published'
       AND i.expires_at IS NOT NULL
       AND i.expires_at <= now()
    RETURNING i.*
  LOOP
    -- Haftalar önce dolmuş (bozuk iş yüzünden bekleyen) ilanlar sessizce
    -- kapanır; bildirim yalnız son 7 günde dolanlara.
    IF v.expires_at >= now() - interval '7 days' THEN
      PERFORM private.ilan_expiry_notify(v, 'expired');
    END IF;
  END LOOP;
  PERFORM set_config('cizre.ilan_system_write', 'off', true);
END;
$fn$;

REVOKE ALL ON FUNCTION public.expire_stale_ilanlar() FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4) Süreyi uzat (sahibi)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.extend_my_ilan(p_ilan_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_me uuid := auth.uid();
  v public.ilanlar%ROWTYPE;
  v_settings public.ilan_settings%ROWTYPE;
  v_fee numeric(10,2);
  v_active integer;
  v_balance_id uuid;
  v_balance numeric(12,2);
  v_new_expiry timestamptz;
  v_republish boolean;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Giriş yapmalısın' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v FROM public.ilanlar i WHERE i.id = p_ilan_id FOR UPDATE;
  IF NOT FOUND OR v.owner_id IS DISTINCT FROM v_me THEN
    RAISE EXCEPTION 'İlan bulunamadı' USING ERRCODE = 'P0001', HINT = 'ILAN_NOT_FOUND';
  END IF;

  SELECT * INTO v_settings FROM public.ilan_settings s WHERE s.id = 1;
  IF NOT COALESCE(v_settings.is_enabled, false) THEN
    RAISE EXCEPTION 'İlan sistemi şu anda kapalı' USING ERRCODE = 'P0001', HINT = 'ILAN_DISABLED';
  END IF;

  v_republish := v.status = 'expired'
    OR (v.status = 'published' AND v.expires_at IS NOT NULL AND v.expires_at <= now());
  IF NOT v_republish AND (v.status <> 'published' OR v.expires_at IS NULL) THEN
    RAISE EXCEPTION 'Bu ilanın süresi uzatılamaz' USING ERRCODE = 'P0001', HINT = 'ILAN_NOT_EXTENDABLE';
  END IF;
  IF NOT v_republish AND v.expires_at > now() + interval '7 days' THEN
    RAISE EXCEPTION 'Süreyi, bitimine 7 günden az kalınca uzatabilirsin' USING ERRCODE = 'P0001', HINT = 'ILAN_TOO_EARLY';
  END IF;

  IF v_republish THEN
    -- Yeniden yayın: etkin ilan sınırı (yeni ilandaki gibi).
    SELECT count(*) INTO v_active
      FROM public.ilanlar i
     WHERE i.owner_id = v_me
       AND i.id <> v.id
       AND i.status IN ('draft', 'pending', 'published')
       AND (i.status <> 'published' OR i.expires_at IS NULL OR i.expires_at > now());
    IF v_active >= v_settings.max_active_per_user THEN
      RAISE EXCEPTION 'Aktif ilan limitine ulaştın' USING ERRCODE = 'P0001', HINT = 'ILAN_ACTIVE_LIMIT';
    END IF;

    -- Kategori yayın ücreti yeni yayın dönemi için yeniden alınır (varsa).
    SELECT c.publish_fee INTO v_fee FROM public.ilan_categories c WHERE c.id = v.category_id;
    IF COALESCE(v_fee, 0) > 0 THEN
      SELECT ub.id, ub.balance INTO v_balance_id, v_balance
        FROM public.user_balances ub WHERE ub.user_id = v_me FOR UPDATE;
      IF v_balance_id IS NULL OR v_balance < v_fee THEN
        RAISE EXCEPTION 'Yetersiz bakiye: bu kategoride yayın süresi % TL', v_fee
          USING ERRCODE = 'P0001', HINT = 'ILAN_INSUFFICIENT_BALANCE';
      END IF;
      UPDATE public.user_balances
         SET balance = v_balance - v_fee, total_spent = total_spent + v_fee, updated_at = now()
       WHERE id = v_balance_id;
      INSERT INTO public.balance_transactions (
        user_id, type, amount, net_amount, balance_before, balance_after,
        reference_type, reference_id, status, description
      ) VALUES (
        v_me, 'ilan_publish_fee'::public.balance_transaction_type, v_fee, v_fee,
        v_balance, v_balance - v_fee, 'ilan', v.id, 'completed',
        format('İlan süresi uzatma ücreti: %s', left(v.title, 120))
      );
    END IF;
    v_new_expiry := now() + make_interval(days => v_settings.default_expiry_days);
  ELSE
    v_new_expiry := v.expires_at + make_interval(days => v_settings.default_expiry_days);
  END IF;

  PERFORM set_config('cizre.ilan_system_write', 'on', true);
  UPDATE public.ilanlar i
     SET status = 'published',
         expires_at = v_new_expiry,
         published_at = CASE WHEN v_republish THEN now() ELSE i.published_at END,
         paid_fee = CASE WHEN COALESCE(v_fee, 0) > 0 THEN v_fee ELSE i.paid_fee END,
         fee_refunded = CASE WHEN COALESCE(v_fee, 0) > 0 THEN false ELSE i.fee_refunded END
   WHERE i.id = v.id;
  PERFORM set_config('cizre.ilan_system_write', 'off', true);

  -- Eski hatırlatmalar artık geçersiz.
  DELETE FROM public.notifications n
   WHERE n.user_id = v_me
     AND n.type IN ('ilan_expiring', 'ilan_expired')
     AND n.entity_id = v.id::text;

  RETURN jsonb_build_object(
    'status', 'published',
    'expires_at', v_new_expiry,
    'republished', v_republish,
    'days', v_settings.default_expiry_days,
    'fee', COALESCE(v_fee, 0)
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.extend_my_ilan(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.extend_my_ilan(uuid) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

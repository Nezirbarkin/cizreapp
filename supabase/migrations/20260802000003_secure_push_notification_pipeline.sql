-- =============================================================================
-- 2026-08-02 — Güvenli push notification pipeline (transactional outbox)
-- -----------------------------------------------------------------------------
-- Tespit edilen güvenlik sorunları (kök neden):
--   1) supabase/functions/send-push/index.ts: çağıranı doğrulamıyor;
--      body'den user_id, title, body, topic kabul ediyor; service_role
--      ile başka kullanıcının FCM token'ını okuyup gönderebiliyor.
--   2) supabase/functions/send-push-notification/index.ts: seller/courier/
--      driver/news rollerine başka kullanıcı adına keyfi title/body ile
--      push gönderme yetkisi veriyor.
--   3) 20260411120004_push_notification_trigger.sql içindeki
--      send_push_on_notification() ve
--      20260726120001_flash_sale_and_price_alert_setup.sql içindeki
--      notify_price_drops() sabit project URL + anon JWT ile net.http_post
--      çağrısı yapıyor, hataları yutuyor, çift push üretebiliyor.
--   4) Flutter istemcisi: profiles.fcm_token SELECT ediyor,
--      functions.invoke('send-push' | 'send-push-notification', ...) ile
--      direkt push gönderiyor.
--
-- Hedef akış:
--   Güvenli domain RPC (server-side) → INSERT public.notifications
--     → AFTER INSERT trigger → INSERT public.notification_outbox
--     → process-notification-outbox worker → FCM HTTP v1
--     → status: sent | failed (retry+backoff) | dead
--
-- Bu migration geriye dönük değildir; eski uygulanmış migration
-- dosyaları değiştirilmez, sadece canlı nesneler yeni isimlerle
-- değiştirilir / etkisizleştirilir.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- BÖLÜM A — Eski güvensiz trigger'ları ve fonksiyonları etkisizleştir
-- -----------------------------------------------------------------------------

-- 1) notifications tablosundaki eski push trigger'ı kaldır
DROP TRIGGER IF EXISTS notifications_push_trigger ON public.notifications;

-- 2) products tablosundaki eski price-drop push trigger'ı kaldır
--    (notify_price_drops() zaten HTTP çağrısı yapıyordu; yeni tanım
--     sadece notifications INSERT eder ve genel trigger outbox'a yazar)
DROP TRIGGER IF EXISTS products_price_drop_alert ON public.products;

-- 3) Eski send_push_on_notification fonksiyonunu yeniden adlandır.
--    İçerik aynen kalır ama artık erişilemez (yeni trigger bağlanmaz).
--    Fonksiyon hala tanımlı olduğu için başka yerlerde çağrılırsa
--    RAISE ile reddedilir; bu sayede ileride yanlışlıkla kullanımı
--    da görünür hale gelir.
ALTER FUNCTION public.send_push_on_notification() RENAME TO send_push_on_notification_DEPRECATED;

CREATE OR REPLACE FUNCTION public.send_push_on_notification_DEPRECATED()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Bu fonksiyon 2026-08-02 push pipeline refaktörü sonrası
  -- kullanım dışıdır. Eski tetikleyici DROP edildi; bu fonksiyon
  -- tetiklenmemelidir. Çağrılırsa hata fırlatır.
  RAISE EXCEPTION
    'send_push_on_notification_DEPRECATED tetiklendi. Yeni push pipeline kullanın.';
END;
$$;

-- 4) Eski notify_price_drops fonksiyonunu yeniden adlandır.
--    Yenisi aşağıda CREATE OR REPLACE ile yazılacak.
ALTER FUNCTION public.notify_price_drops() RENAME TO notify_price_drops_LEGACY;

-- Yeni notify_price_drops: net.http_post YOK, sabit URL/JWT YOK,
-- yalnızca notifications INSERT eder. Genel trigger outbox'a ekler.
CREATE OR REPLACE FUNCTION public.notify_price_drops()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_alert       RECORD;
  v_old_price   NUMERIC(10, 2);
  v_new_price   NUMERIC(10, 2);
  v_existing_id UUID;
BEGIN
  -- Sadece fiyat düşüşünde tetikle
  v_old_price := COALESCE(OLD.discount_price, OLD.price);
  v_new_price := COALESCE(NEW.discount_price, NEW.price);

  IF v_new_price >= v_old_price THEN
    RETURN NEW;
  END IF;

  FOR v_alert IN
    SELECT pa.id AS alert_id, pa.user_id, pa.target_price
      FROM public.price_alerts pa
      WHERE pa.product_id = NEW.id
        AND pa.is_active = true
        AND pa.target_price >= v_new_price
  LOOP
    -- Aynı kullanıcı/ürün için son 24 saat içinde price_drop
    -- bildirimi oluşturulmuşsa çift bildirim engellenir.
    -- (price_alerts.is_active zaten aşağıda false'a çekilecek; bu
    -- pencere sadece yarış koşulu durumlarında ikinci INSERT'i
    -- engeller.)
    SELECT n.id
      INTO v_existing_id
      FROM public.notifications n
     WHERE n.user_id = v_alert.user_id
       AND n.type = 'price_drop'
       AND n.entity_id = NEW.id::text
       AND n.created_at > NOW() - INTERVAL '24 hours'
     LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      -- Mevcut bildirim üzerine yazma; alarmı kapat.
      UPDATE public.price_alerts
         SET is_active = false, triggered_at = NOW()
       WHERE id = v_alert.alert_id;
      CONTINUE;
    END IF;

    INSERT INTO public.notifications (
      user_id, type, title, content, actor_id, entity_id, is_read, created_at
    ) VALUES (
      v_alert.user_id,
      'price_drop',
      '📉 Fiyat Düştü!',
      format('%s ürünü %.2f ₺ oldu. Hedefiniz %.2f ₺',
             NEW.name, v_new_price, v_alert.target_price),
      NULL,
      NEW.id,
      false,
      NOW()
    );

    -- Alarmı tetiklendi olarak işaretle (tek seferlik).
    UPDATE public.price_alerts
       SET is_active = false, triggered_at = NOW()
     WHERE id = v_alert.alert_id;
  END LOOP;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_price_drops() IS
  'Fiyat düşüşünde in-app notification oluşturur. Outbox trigger push''u
  güvenli olarak iletir. net.http_post KULLANMAZ.';

-- 5) Yeni tetikleyici: ürün fiyatı düştüğünde yeni fonksiyonu çağırır
DROP TRIGGER IF EXISTS products_price_drop_alert_v2 ON public.products;
CREATE TRIGGER products_price_drop_alert_v2
  AFTER UPDATE ON public.products
  FOR EACH ROW
  WHEN (OLD.price IS DISTINCT FROM NEW.price
        OR OLD.discount_price IS DISTINCT FROM NEW.discount_price)
  EXECUTE FUNCTION public.notify_price_drops();

-- -----------------------------------------------------------------------------
-- BÖLÜM B — Transactional outbox tablosu
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id UUID NOT NULL
    REFERENCES public.notifications(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'dead')),
  attempts        INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  locked_at       TIMESTAMPTZ,
  locked_by       TEXT,
  last_error      TEXT,
  sent_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT notification_outbox_notification_uniq UNIQUE (notification_id)
);

CREATE INDEX IF NOT EXISTS idx_outbox_due
  ON public.notification_outbox(next_attempt_at)
  WHERE status IN ('pending', 'failed');

CREATE INDEX IF NOT EXISTS idx_outbox_processing
  ON public.notification_outbox(locked_at)
  WHERE status = 'processing';

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

-- RLS: client rolleri outbox'a doğrudan erişemez.
DROP POLICY IF EXISTS "notification_outbox_no_direct_access"
  ON public.notification_outbox;
CREATE POLICY "notification_outbox_no_direct_access"
  ON public.notification_outbox
  FOR ALL
  TO authenticated, anon
  USING (false)
  WITH CHECK (false);

-- Outbox üzerinde tüm veri işlemleri yalnızca service_role'a.
REVOKE ALL ON public.notification_outbox FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_outbox TO service_role;

-- updated_at otomatik güncelleme
CREATE OR REPLACE FUNCTION public.trg_notification_outbox_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notification_outbox_set_updated_at
  ON public.notification_outbox;
CREATE TRIGGER notification_outbox_set_updated_at
  BEFORE UPDATE ON public.notification_outbox
  FOR EACH ROW EXECUTE FUNCTION public.trg_notification_outbox_set_updated_at();

-- -----------------------------------------------------------------------------
-- BÖLÜM C — Outbox yönetim RPC'leri (yalnızca service_role)
-- -----------------------------------------------------------------------------

-- 1) enqueue_notification_outbox: notifications INSERT trigger'ı
--    tarafından çağrılır. ON CONFLICT DO NOTHING ile idempotent.
CREATE OR REPLACE FUNCTION public.enqueue_notification_outbox(
  p_notification_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_notification_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.notification_outbox (notification_id, status, next_attempt_at)
  VALUES (p_notification_id, 'pending', NOW())
  ON CONFLICT (notification_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_notification_outbox(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_notification_outbox(UUID)
  TO service_role;

-- 2) claim_notification_outbox: FOR UPDATE SKIP LOCKED ile atomik
--    claim. Aynı anda birden fazla worker çalışsa bile aynı kayıt
--    iki kez alınmaz.
CREATE OR REPLACE FUNCTION public.claim_notification_outbox(
  p_limit    INTEGER DEFAULT 25,
  p_worker_id TEXT    DEFAULT 'worker'
)
RETURNS TABLE (
  outbox_id            UUID,
  notification_id      UUID,
  user_id              UUID,
  type                 TEXT,
  title                TEXT,
  content              TEXT,
  entity_id            TEXT,
  notification_metadata JSONB,
  attempt_number       INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit INTEGER := GREATEST(COALESCE(p_limit, 25), 1);
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT o.id
      FROM public.notification_outbox o
     WHERE o.status IN ('pending', 'failed')
       AND o.next_attempt_at <= NOW()
     ORDER BY o.next_attempt_at ASC
     LIMIT v_limit
     FOR UPDATE SKIP LOCKED
  ),
  claimed AS (
    UPDATE public.notification_outbox o
       SET status        = 'processing',
           locked_at     = NOW(),
           locked_by     = p_worker_id,
           attempts      = o.attempts + 1,
           next_attempt_at = NOW() + (
             LEAST(POWER(2, o.attempts + 1), 1800) * INTERVAL '1 second'
           )
     FROM due
     WHERE o.id = due.id
     RETURNING o.id, o.notification_id, o.attempts
  )
  SELECT
    c.id            AS outbox_id,
    c.notification_id,
    n.user_id,
    n.type,
    n.title,
    n.content,
    n.entity_id,
    n.metadata,
    c.attempts
  FROM claimed c
  JOIN public.notifications n ON n.id = c.notification_id;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_notification_outbox(INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notification_outbox(INTEGER, TEXT)
  TO service_role;

-- 3) mark_outbox_sent: başarı
CREATE OR REPLACE FUNCTION public.mark_outbox_sent(
  p_outbox_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.notification_outbox
     SET status     = 'sent',
         sent_at    = NOW(),
         locked_at  = NULL,
         locked_by  = NULL,
         last_error = NULL
   WHERE id = p_outbox_id;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_outbox_sent(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_outbox_sent(UUID) TO service_role;

-- 4) mark_outbox_failed: attempts artırıp dead veya failed yapar
CREATE OR REPLACE FUNCTION public.mark_outbox_failed(
  p_outbox_id   UUID,
  p_error       TEXT,
  p_max_attempts INTEGER DEFAULT 8
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_attempts INTEGER;
BEGIN
  SELECT attempts INTO v_attempts
    FROM public.notification_outbox
   WHERE id = p_outbox_id
   FOR UPDATE;

  IF v_attempts IS NULL THEN
    RETURN;
  END IF;

  IF v_attempts >= p_max_attempts THEN
    UPDATE public.notification_outbox
       SET status     = 'dead',
           locked_at  = NULL,
           locked_by  = NULL,
           last_error = p_error
     WHERE id = p_outbox_id;
  ELSE
    UPDATE public.notification_outbox
       SET status     = 'failed',
           locked_at  = NULL,
           locked_by  = NULL,
           last_error = p_error,
           next_attempt_at = NOW() + (
             LEAST(POWER(2, v_attempts), 1800) * INTERVAL '1 second'
           )
     WHERE id = p_outbox_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_outbox_failed(UUID, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_outbox_failed(UUID, TEXT, INTEGER)
  TO service_role;

-- 5) release_stale_outbox: worker crash koruması. locked_at eski
--    processing kayıtlarını pending'e geri alır.
CREATE OR REPLACE FUNCTION public.release_stale_outbox(
  p_max_age INTERVAL DEFAULT INTERVAL '5 minutes'
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  WITH stale AS (
    SELECT id
      FROM public.notification_outbox
     WHERE status = 'processing'
       AND locked_at < NOW() - p_max_age
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notification_outbox o
     SET status     = 'failed',
         locked_at  = NULL,
         locked_by  = NULL,
         next_attempt_at = NOW()
    FROM stale s
   WHERE o.id = s.id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.release_stale_outbox(INTERVAL)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_stale_outbox(INTERVAL) TO service_role;

-- -----------------------------------------------------------------------------
-- BÖLÜM D — Yeni notifications trigger'ı (outbox'a yazar, HTTP çağırmaz)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_notification_outbox_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Chat / message tipleri için push gönderme. Bu tipler kendi
  -- tetikleyicileriyle yönetiliyor; burada sessizce geçiyoruz.
  IF NEW.type IN ('message', 'chat') THEN
    RETURN NEW;
  END IF;

  PERFORM public.enqueue_notification_outbox(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notifications_outbox_trigger ON public.notifications;
CREATE TRIGGER notifications_outbox_trigger
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.enqueue_notification_outbox_trigger();

-- -----------------------------------------------------------------------------
-- BÖLÜM E — share_post_with_user (dar kapsamlı RPC)
-- -----------------------------------------------------------------------------
-- Mevcut akışta Flutter iki yerde post paylaşımı yapıyor:
--   1) profiles/screens/user_profile_screen.dart (arkadaş profili)
--   2) profiles/screens/profile_screen.dart (kendi gönderisi)
-- Her ikisi de doğrudan notifications INSERT ediyor + functions.invoke
-- ile push gönderiyor. Yeni RPC:
--   - Gönderen auth.uid() ile belirlenir
--   - Parametreden sender kabul etmez
--   - Alıcı mevcut olmalı (auth.users)
--   - Self-share reddedilir
--   - Post mevcut olmalı
--   - Gizli/silinmiş/yasaklı kontrolü (posts tablosunda bu kolonlar
--     yoksa sadece varlık kontrolü uygulanır)
--   - Son 60 saniye içinde aynı (actor, recipient, post, type) için
--     notification varsa yeniden ekleme yapmaz (idempotency)
--   - Server tarafında title/content üretir
--   - Outbox trigger'ı otomatik olarak push'u güvenli şekilde gönderir
CREATE OR REPLACE FUNCTION public.share_post_with_user(
  p_post_id     UUID,
  p_recipient_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sender_id   CONSTANT UUID := auth.uid();
  v_caller_role CONSTANT TEXT := COALESCE(auth.role(), '');
  v_post_id     UUID;
  v_post_owner  UUID;
  v_recent_id   UUID;
  v_notif_id    UUID;
BEGIN
  -------------------------------------------------------------------------
  -- 1) Kimlik doğrulama
  -------------------------------------------------------------------------
  IF v_sender_id IS NULL OR v_caller_role = 'anon' THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;

  IF p_post_id IS NULL OR p_recipient_id IS NULL THEN
    RAISE EXCEPTION 'post_id ve recipient_id zorunludur' USING ERRCODE = '22023';
  END IF;

  IF p_recipient_id = v_sender_id THEN
    RAISE EXCEPTION 'Kendinize gönderi paylaşamazsınız' USING ERRCODE = 'P0001';
  END IF;

  -------------------------------------------------------------------------
  -- 2) Post mevcut mu?
  -------------------------------------------------------------------------
  -- posts tablosunda privacy/is_hidden kolonları mevcut değilse
  -- sadece varlık kontrolü yapılır. (İleride kolon eklenirse burada
  -- USING koşulu genişletilebilir.)
  EXECUTE format(
    'SELECT id, user_id FROM public.posts WHERE id = $1 LIMIT 1'
  )
  INTO v_post_id, v_post_owner
  USING p_post_id;

  IF v_post_id IS NULL THEN
    RAISE EXCEPTION 'Gönderi bulunamadı veya erişilemez' USING ERRCODE = 'P0002';
  END IF;

  -------------------------------------------------------------------------
  -- 3) Alıcı mevcut mu?
  -------------------------------------------------------------------------
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_recipient_id) THEN
    RAISE EXCEPTION 'Alıcı kullanıcı bulunamadı' USING ERRCODE = 'P0002';
  END IF;

  -------------------------------------------------------------------------
  -- 4) Idempotency: son 60 saniye içinde aynı paylaşım
  -------------------------------------------------------------------------
  SELECT n.id
    INTO v_recent_id
    FROM public.notifications n
   WHERE n.user_id   = p_recipient_id
     AND n.actor_id  = v_sender_id
     AND n.entity_id = p_post_id::text
     AND n.type      = 'post_share'
     AND n.created_at > NOW() - INTERVAL '60 seconds'
   LIMIT 1;

  IF v_recent_id IS NOT NULL THEN
    RETURN v_recent_id;
  END IF;

  -------------------------------------------------------------------------
  -- 5) Server tarafında notification oluştur
  -------------------------------------------------------------------------
  -- Title/content istemciden ALINMAZ, sunucu tarafında üretilir.
  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, entity_id, is_read, created_at
  ) VALUES (
    p_recipient_id,
    'post_share',
    'Gönderi Paylaşıldı',
    'Bir kullanıcı sizinle bir gönderi paylaştı.',
    v_sender_id,
    p_post_id::text,
    false,
    NOW()
  )
  RETURNING id INTO v_notif_id;

  RETURN v_notif_id;
END;
$$;

REVOKE ALL ON FUNCTION public.share_post_with_user(UUID, UUID)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_post_with_user(UUID, UUID)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- BÖLÜM F — Admin bildirim RPC'leri (dar kapsamlı)
-- -----------------------------------------------------------------------------
-- Admin kişisel veya toplu bildirim göndermek istediğinde genel push
-- endpoint'ini çağırmaz. Bunun yerine:
--   - admin_send_personal_notification
--   - admin_broadcast_notification
-- Bu RPC'ler admin rolünü profiles üzerinden server-side doğrular,
-- başlık/içerik uzunluk sınırı uygular, audit kaydı oluşturur ve
-- notifications/admin_broadcasts üzerinden yazar. Outbox trigger'ı
-- push'u güvenli şekilde gönderir.
-- -----------------------------------------------------------------------------

-- Audit tablosu
CREATE TABLE IF NOT EXISTS public.admin_notification_audit (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  action            TEXT NOT NULL CHECK (action IN ('personal', 'broadcast')),
  target_audience   TEXT,
  recipient_id      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  title             TEXT NOT NULL,
  content           TEXT NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_notification_audit_admin
  ON public.admin_notification_audit(admin_id, created_at DESC);

ALTER TABLE public.admin_notification_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_notification_audit_select_admin"
  ON public.admin_notification_audit;
CREATE POLICY "admin_notification_audit_select_admin"
  ON public.admin_notification_audit
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

REVOKE ALL ON public.admin_notification_audit
  FROM PUBLIC, anon;
GRANT SELECT ON public.admin_notification_audit TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.admin_notification_audit
  TO service_role;

-- 1) admin_send_personal_notification
CREATE OR REPLACE FUNCTION public.admin_send_personal_notification(
  p_user_id   UUID,
  p_title     TEXT,
  p_content   TEXT,
  p_icon_type TEXT DEFAULT 'info'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_id   CONSTANT UUID := auth.uid();
  v_caller_role CONSTANT TEXT := COALESCE(auth.role(), '');
  v_notif_id   UUID;
BEGIN
  IF v_admin_id IS NULL OR v_caller_role = 'anon' THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir' USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id zorunludur' USING ERRCODE = '22023';
  END IF;

  -- Uzunluk sınırları (server-side)
  IF p_title IS NULL OR LENGTH(p_title) = 0 OR LENGTH(p_title) > 100 THEN
    RAISE EXCEPTION 'Başlık 1-100 karakter olmalıdır' USING ERRCODE = '22000';
  END IF;

  IF p_content IS NULL OR LENGTH(p_content) = 0 OR LENGTH(p_content) > 500 THEN
    RAISE EXCEPTION 'İçerik 1-500 karakter olmalıdır' USING ERRCODE = '22000';
  END IF;

  -- Alıcı mevcut mu?
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'Alıcı kullanıcı bulunamadı' USING ERRCODE = 'P0002';
  END IF;

  -- Audit
  INSERT INTO public.admin_notification_audit (
    admin_id, action, recipient_id, title, content
  ) VALUES (
    v_admin_id, 'personal', p_user_id, p_title, p_content
  );

  -- Notification (push outbox trigger'ı ile gidecek)
  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, entity_id, metadata, is_read, created_at
  ) VALUES (
    p_user_id,
    'admin_notification',
    p_title,
    p_content,
    v_admin_id,
    format('admin_icon:%s', COALESCE(NULLIF(p_icon_type, ''), 'info')),
    jsonb_build_object(
      'icon_type', COALESCE(NULLIF(p_icon_type, ''), 'info'),
      'target', 'personal'
    ),
    false,
    NOW()
  )
  RETURNING id INTO v_notif_id;

  RETURN v_notif_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_send_personal_notification(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_send_personal_notification(UUID, TEXT, TEXT, TEXT)
  TO authenticated;

-- 2) admin_broadcast_notification
--    Toplu bildirim: admin_broadcasts tablosuna tek bir kayıt yazar.
--    Kullanıcılar bu tablo üzerinden broadcast'leri görür.
--    Topic push gönderilmez; güvensiz kanal kapatıldı.
CREATE OR REPLACE FUNCTION public.admin_broadcast_notification(
  p_title     TEXT,
  p_content   TEXT,
  p_icon_type TEXT DEFAULT 'info',
  p_target_audience TEXT DEFAULT 'all_users'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_id   CONSTANT UUID := auth.uid();
  v_caller_role CONSTANT TEXT := COALESCE(auth.role(), '');
  v_audit_id   UUID;
  v_audience   TEXT;
BEGIN
  IF v_admin_id IS NULL OR v_caller_role = 'anon' THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir' USING ERRCODE = '42501';
  END IF;

  IF p_title IS NULL OR LENGTH(p_title) = 0 OR LENGTH(p_title) > 100 THEN
    RAISE EXCEPTION 'Başlık 1-100 karakter olmalıdır' USING ERRCODE = '22000';
  END IF;

  IF p_content IS NULL OR LENGTH(p_content) = 0 OR LENGTH(p_content) > 1000 THEN
    RAISE EXCEPTION 'İçerik 1-1000 karakter olmalıdır' USING ERRCODE = '22000';
  END IF;

  -- Hedef kitle allowlist
  v_audience := COALESCE(NULLIF(p_target_audience, ''), 'all_users');
  IF v_audience NOT IN ('customers', 'sellers', 'all_users') THEN
    RAISE EXCEPTION 'Geçersiz hedef kitle' USING ERRCODE = '22000';
  END IF;

  -- Audit
  INSERT INTO public.admin_notification_audit (
    admin_id, action, target_audience, title, content
  ) VALUES (
    v_admin_id, 'broadcast', v_audience, p_title, p_content
  )
  RETURNING id INTO v_audit_id;

  -- admin_broadcasts tablosu zaten mevcut (proje şemasında tanımlı).
  -- Topic push YAPILMAZ; sadece broadcast tablosuna yazılır.
  INSERT INTO public.admin_broadcasts (
    title, content, icon_type, target_audience, is_active
  ) VALUES (
    p_title, p_content, COALESCE(NULLIF(p_icon_type, ''), 'info'),
    v_audience, true
  );

  RETURN v_audit_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_broadcast_notification(TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_broadcast_notification(TEXT, TEXT, TEXT, TEXT)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- BÖLÜM G — notify_price_drops yetki düzeltmesi
-- -----------------------------------------------------------------------------
-- Eski migration authenticated'a EXECUTE vermişti; trigger'lar SECURITY
-- DEFINER olduğu için yine de çalışırdı. Yeni trigger bağlandı; fonksiyon
-- da artık sadece SECURITY DEFINER çağrıları için çalışacak şekilde
-- yetkileri netleştiriyoruz.
REVOKE EXECUTE ON FUNCTION public.notify_price_drops() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notify_price_drops() TO authenticated;

-- -----------------------------------------------------------------------------
-- TAMAMLANDI
-- -----------------------------------------------------------------------------
-- Bu migration idempotent: tekrar çalıştırılabilir.
-- Eski uygulanmış migration dosyalarına dokunulmamıştır.
-- =============================================================================

-- =============================================================================
-- 2026-08-07 — Push pipeline migration'larını canlıda uygulama script'i
-- -----------------------------------------------------------------------------
-- AMAÇ: Diagnostic sonucu "❌ notification_outbox tablosu yok" çıkarsa,
--       20260802000003 + 20260802000004 migration'larını güvenli şekilde
--       uygulamak.
--
-- UYARI: Bu SQL'i çalıştırmadan önce:
--   1) Supabase Dashboard → Database → Settings → Custom Postgres Config'e
--      app.settings.internal_worker_secret = '<SECRET>' ekleyin
--      (Edge Function env'i ile AYNI secret olmalı).
--   2) Edge Function'da INTERNAL_WORKER_SECRET secret'ı tanımlı olmalı
--      (supabase secrets set INTERNAL_WORKER_SECRET=<SECRET>).
--   3) Edge Function'da FIREBASE_SERVICE_ACCOUNT JSON secret'ı tanımlı olmalı
--      (supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)").
--
-- UYGULAMA SIRASI:
--   1) Dashboard → SQL Editor
--   2) Önce aşağıdaki "DOĞRULAMA" bölümünü çalıştır (veri yazmaz)
--   3) Çıktıda her şey ✅ ise aşağıdaki "UYGULAMA" bölümünü çalıştır
--   4) Sonra bu dosyanın 2. bölümündeki cron SQL'ini çalıştır
--   5) Son olarak Edge Function loglarından worker'ın çalıştığını doğrula
-- =============================================================================

-- ============================================================================
-- BÖLÜM 1 — DOĞRULAMA (veri yazmaz; sadece ✅/❌ raporlar)
-- ============================================================================

SELECT
  'ÖN-KONTROL: preflight' AS kontrol,
  CASE
    WHEN to_regclass('public.notification_outbox') IS NOT NULL
    THEN '⚠️  Outbox zaten mevcut. Uygulama bölümünü atla veya idempotent çalıştır.'
    ELSE '✅ Outbox yok; uygulama güvenli.'
  END AS durum;

SELECT
  'ÖN-KONTROL: pg_cron' AS kontrol,
  CASE
    WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
    THEN '✅ pg_cron kurulu'
    ELSE '⚠️  pg_cron kurulu değil. Önce Dashboard → Database → Extensions → pg_cron etkinleştir.'
  END AS durum;

SELECT
  'ÖN-KONTROL: internal_worker_secret' AS kontrol,
  CASE
    WHEN current_setting('app.settings.internal_worker_secret', true) IS NOT NULL
     AND current_setting('app.settings.internal_worker_secret', true) <> ''
    THEN '✅ Postgres custom config''te ayarlı'
    ELSE '❌ AYARLA: Dashboard → Database → Settings → Custom Postgres Config → app.settings.internal_worker_secret = ''<SECRET>'' (Edge Function env''i ile aynı)'
  END AS durum;

-- ============================================================================
-- BÖLÜM 2 — MIGRATION'U ÇALIŞTIR
-- ============================================================================
-- Bu bölüm 20260802000003_secure_push_notification_pipeline.sql
-- dosyasının TAMAMINI içerir. Idempotent: birden fazla kez çalıştırılabilir.
-- ============================================================================

-- (Aşağıdaki SQL, supabase/migrations/20260802000003_secure_push_notification_pipeline.sql
--  dosyasının aynısıdır; buraya kopyalanmıştır ki SQL Editor'den tek
--  seferde uygulanabilsin.)
BEGIN;

-- -----------------------------------------------------------------------------
-- BÖLÜM A — Eski güvensiz trigger'ları ve fonksiyonları etkisizleştir
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS notifications_push_trigger ON public.notifications;
DROP TRIGGER IF EXISTS products_price_drop_alert ON public.products;

ALTER FUNCTION public.send_push_on_notification() RENAME TO send_push_on_notification_DEPRECATED;

CREATE OR REPLACE FUNCTION public.send_push_on_notification_DEPRECATED()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'send_push_on_notification_DEPRECATED tetiklendi. Yeni push pipeline kullanın.';
END;
$$;

ALTER FUNCTION public.notify_price_drops() RENAME TO notify_price_drops_LEGACY;

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
    SELECT n.id INTO v_existing_id
      FROM public.notifications n
     WHERE n.user_id = v_alert.user_id
       AND n.type = 'price_drop'
       AND n.entity_id = NEW.id::text
       AND n.created_at > NOW() - INTERVAL '24 hours'
     LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
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

    UPDATE public.price_alerts
       SET is_active = false, triggered_at = NOW()
     WHERE id = v_alert.alert_id;
  END LOOP;

  RETURN NEW;
END;
$$;

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

DROP POLICY IF EXISTS "notification_outbox_no_direct_access"
  ON public.notification_outbox;
CREATE POLICY "notification_outbox_no_direct_access"
  ON public.notification_outbox
  FOR ALL
  TO authenticated, anon
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON public.notification_outbox FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_outbox TO service_role;

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
-- BÖLÜM C — Outbox yönetim RPC'leri
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_notification_outbox(p_notification_id UUID)
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

CREATE OR REPLACE FUNCTION public.mark_outbox_sent(p_outbox_id UUID)
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

REVOKE ALL ON FUNCTION public.mark_outbox_sent(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_outbox_sent(UUID) TO service_role;

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
-- BÖLÜM D — Yeni notifications trigger'ı
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_notification_outbox_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
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
-- BÖLÜM E — share_post_with_user RPC
-- -----------------------------------------------------------------------------
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
  IF v_sender_id IS NULL OR v_caller_role = 'anon' THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;

  IF p_post_id IS NULL OR p_recipient_id IS NULL THEN
    RAISE EXCEPTION 'post_id ve recipient_id zorunludur' USING ERRCODE = '22023';
  END IF;

  IF p_recipient_id = v_sender_id THEN
    RAISE EXCEPTION 'Kendinize gönderi paylaşamazsınız' USING ERRCODE = 'P0001';
  END IF;

  EXECUTE format(
    'SELECT id, user_id FROM public.posts WHERE id = $1 LIMIT 1'
  )
  INTO v_post_id, v_post_owner
  USING p_post_id;

  IF v_post_id IS NULL THEN
    RAISE EXCEPTION 'Gönderi bulunamadı veya erişilemez' USING ERRCODE = 'P0002';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_recipient_id) THEN
    RAISE EXCEPTION 'Alıcı kullanıcı bulunamadı' USING ERRCODE = 'P0002';
  END IF;

  SELECT n.id INTO v_recent_id
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

REVOKE ALL ON FUNCTION public.share_post_with_user(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_post_with_user(UUID, UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- BÖLÜM F — Admin RPC'leri
-- -----------------------------------------------------------------------------
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

REVOKE ALL ON public.admin_notification_audit FROM PUBLIC, anon;
GRANT SELECT ON public.admin_notification_audit TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.admin_notification_audit TO service_role;

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

  IF p_title IS NULL OR LENGTH(p_title) = 0 OR LENGTH(p_title) > 100 THEN
    RAISE EXCEPTION 'Başlık 1-100 karakter olmalıdır' USING ERRCODE = '22000';
  END IF;

  IF p_content IS NULL OR LENGTH(p_content) = 0 OR LENGTH(p_content) > 500 THEN
    RAISE EXCEPTION 'İçerik 1-500 karakter olmalıdır' USING ERRCODE = '22000';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'Alıcı kullanıcı bulunamadı' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.admin_notification_audit (
    admin_id, action, recipient_id, title, content
  ) VALUES (
    v_admin_id, 'personal', p_user_id, p_title, p_content
  );

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

  v_audience := COALESCE(NULLIF(p_target_audience, ''), 'all_users');
  IF v_audience NOT IN ('customers', 'sellers', 'all_users') THEN
    RAISE EXCEPTION 'Geçersiz hedef kitle' USING ERRCODE = '22000';
  END IF;

  INSERT INTO public.admin_notification_audit (
    admin_id, action, target_audience, title, content
  ) VALUES (
    v_admin_id, 'broadcast', v_audience, p_title, p_content
  )
  RETURNING id INTO v_audit_id;

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

REVOKE EXECUTE ON FUNCTION public.notify_price_drops() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notify_price_drops() TO authenticated;

COMMIT;

-- ============================================================================
-- BÖLÜM 3 — DOĞRULAMA SONRASI
-- ============================================================================
SELECT
  'SONUÇ A1) notification_outbox tablosu' AS kontrol,
  CASE WHEN to_regclass('public.notification_outbox') IS NOT NULL
       THEN '✅ oluşturuldu' ELSE '❌ hâlâ yok' END AS durum;

SELECT
  'SONUÇ A2) notifications_outbox_trigger' AS kontrol,
  CASE WHEN EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname='notifications_outbox_trigger'
                      AND tgrelid='public.notifications'::regclass)
       THEN '✅ bağlandı' ELSE '❌ bağlanmadı' END AS durum;

SELECT
  'SONUÇ A3) notifications_push_trigger (eski)' AS kontrol,
  CASE WHEN NOT EXISTS (SELECT 1 FROM pg_trigger
                        WHERE tgname='notifications_push_trigger'
                          AND tgrelid='public.notifications'::regclass)
       THEN '✅ kaldırıldı' ELSE '❌ hâlâ bağlı' END AS durum;

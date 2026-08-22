-- ============================================================================
-- E-Fatura altyapısı: invoices + invoice_outbox (2026-08-20)
-- ----------------------------------------------------------------------------
-- AMAÇ: Sipariş teslim edildiğinde bir fatura TASLAĞI oluşturmak; gerçek
-- GİB gönderimi yalnızca admin panelden "Onayla ve Gönder" ile tetiklenir
-- (approve_invoice_and_enqueue). Otomatik/insansız gönderim YOK — alan
-- eşlemesi (Nilvera/Paraşüt request body) henüz canlı API ile doğrulanmadığı
-- için hatalı resmi fatura kesilmesin diye kasıtlı bir insan onay kapısı var.
--
-- Kuyruk/claim deseni courier_assignment_email_outbox
-- (20260812000002_courier_assignment_email_outbox.sql) ile birebir aynı:
-- FOR UPDATE SKIP LOCKED claim, exponential backoff, service_role-only
-- erişim, INTERNAL_WORKER_SECRET korumalı poke trigger.
--
-- invoices tablosu alıcı/fatura bilgisini TEKRARLAMAZ — orders tablosunda
-- zaten var (invoice_type/invoice_full_name/invoice_tax_number/...,
-- 20260710000001_add_invoice_info.sql). Worker, order_id üzerinden join
-- ederek okur.
-- ============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- ============================================================
-- 1. invoices — sipariş başına fatura durumu/belge kaydı
-- ============================================================

CREATE TABLE IF NOT EXISTS public.invoices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider        text CHECK (provider IN ('nilvera', 'parasut')),
  environment     text CHECK (environment IN ('test', 'live')),
  status          text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'queued', 'sent', 'approved', 'rejected', 'cancelled', 'error')),
  invoice_type    text CHECK (invoice_type IN ('e-fatura', 'e-arsiv')),
  external_id     text,
  invoice_number  text,
  kdv_rate        numeric(5, 2),
  kdv_amount      numeric(12, 2),
  net_amount      numeric(12, 2),
  gross_amount    numeric(12, 2),
  pdf_url         text,
  ubl_xml_url     text,
  error_message   text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  queued_at       timestamptz,
  sent_at         timestamptz,
  approved_at     timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT invoices_order_uniq UNIQUE (order_id)
);

CREATE INDEX IF NOT EXISTS idx_invoices_user_id ON public.invoices(user_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON public.invoices(status);

ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "invoices_select_policy" ON public.invoices;
CREATE POLICY "invoices_select_policy" ON public.invoices
  FOR SELECT USING (
    user_id = (select auth.uid())
    OR public.auth_is_admin()
  );

-- Doğrudan INSERT/UPDATE/DELETE yok: taslak trigger ile, onay/gönderim
-- SECURITY DEFINER fonksiyonlarla (approve_invoice_and_enqueue,
-- mark_invoice_sent, mark_invoice_failed) yapılır.
REVOKE ALL ON public.invoices FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.invoices TO authenticated;
GRANT ALL ON public.invoices TO service_role;

-- ============================================================
-- 2. invoice_outbox — gönderim kuyruğu (yalnızca admin onayından
--    sonra satır alır; taslak faturalar bu tabloya hiç girmez)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.invoice_outbox (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id      uuid NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  status          text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'dead')),
  attempts        integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  locked_at       timestamptz,
  locked_by       text,
  last_error      text,
  sent_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT invoice_outbox_invoice_uniq UNIQUE (invoice_id)
);

CREATE INDEX IF NOT EXISTS idx_invoice_outbox_due
  ON public.invoice_outbox(next_attempt_at)
  WHERE status IN ('pending', 'failed');

CREATE INDEX IF NOT EXISTS idx_invoice_outbox_processing
  ON public.invoice_outbox(locked_at)
  WHERE status = 'processing';

ALTER TABLE public.invoice_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "invoice_outbox_no_direct_access" ON public.invoice_outbox;
CREATE POLICY "invoice_outbox_no_direct_access" ON public.invoice_outbox
  FOR ALL
  TO authenticated, anon
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON public.invoice_outbox FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.invoice_outbox TO service_role;

-- ============================================================
-- 3. Taslak oluşturma: sipariş 'delivered' olduğunda
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_invoice_draft_on_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered' THEN
    INSERT INTO public.invoices (
      order_id,
      user_id,
      invoice_type,
      gross_amount
    ) VALUES (
      NEW.id,
      NEW.user_id,
      -- Kurumsal (VKN'li) müşteri -> e-Fatura adayı, bireysel -> e-Arşiv.
      -- NOT: Gerçek e-Fatura mükellefiyeti gönderim anında sağlayıcının
      -- VKN sorgu uç noktasıyla teyit edilmeli; bu sadece ilk tahmin.
      CASE WHEN NEW.invoice_type = 'corporate' THEN 'e-fatura' ELSE 'e-arsiv' END,
      NEW.total_amount
    )
    ON CONFLICT (order_id) DO NOTHING;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Fatura taslağı oluşturulamasa bile sipariş güncellemesi engellenmesin.
  RAISE NOTICE 'create_invoice_draft_on_delivery hatası (görmezden gelindi): %', SQLERRM;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.create_invoice_draft_on_delivery()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_create_invoice_draft ON public.orders;
CREATE TRIGGER trigger_create_invoice_draft
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.create_invoice_draft_on_delivery();

-- ============================================================
-- 4. Admin onayı: taslağı kuyruğa al (fiili gönderim burada BAŞLAMAZ,
--    sadece worker'ın işleyebileceği duruma getirir)
-- ============================================================

CREATE OR REPLACE FUNCTION public.approve_invoice_and_enqueue(p_invoice_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_provider text;
  v_environment text;
  v_outbox_id uuid;
  v_status text;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekli';
  END IF;

  SELECT status INTO v_status FROM public.invoices WHERE id = p_invoice_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Fatura bulunamadı: %', p_invoice_id;
  END IF;
  IF v_status NOT IN ('draft', 'error') THEN
    RAISE EXCEPTION 'Fatura zaten % durumunda, tekrar kuyruğa alınamaz', v_status;
  END IF;

  SELECT value INTO v_provider FROM public.system_settings WHERE key = 'invoice_active_provider';
  SELECT value INTO v_environment FROM public.system_settings WHERE key = 'invoice_environment';

  IF v_provider IS NULL OR v_provider = 'none' THEN
    RAISE EXCEPTION 'Aktif fatura sağlayıcısı seçilmemiş (system_settings.invoice_active_provider)';
  END IF;

  UPDATE public.invoices
  SET status = 'queued',
      provider = v_provider,
      environment = COALESCE(v_environment, 'test'),
      queued_at = now(),
      error_message = NULL,
      updated_at = now()
  WHERE id = p_invoice_id;

  INSERT INTO public.invoice_outbox (invoice_id)
  VALUES (p_invoice_id)
  ON CONFLICT (invoice_id) DO UPDATE
    SET status = 'pending',
        next_attempt_at = now(),
        last_error = NULL,
        updated_at = now()
  RETURNING id INTO v_outbox_id;

  RETURN v_outbox_id;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_invoice_and_enqueue(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_invoice_and_enqueue(uuid) TO authenticated;

-- ============================================================
-- 5. Worker claim/mark fonksiyonları (courier_assignment_email_outbox
--    ile aynı desen)
-- ============================================================

CREATE OR REPLACE FUNCTION public.claim_invoice_outbox(
  p_limit integer DEFAULT 10,
  p_worker_id text DEFAULT 'invoice-worker'
)
RETURNS TABLE (
  outbox_id      uuid,
  invoice_id     uuid,
  order_id       uuid,
  provider       text,
  environment    text,
  invoice_type   text,
  attempt_number integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 10), 1), 50);
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT o.id
    FROM public.invoice_outbox AS o
    WHERE o.status IN ('pending', 'failed')
      AND o.next_attempt_at <= now()
    ORDER BY o.next_attempt_at, o.created_at
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.invoice_outbox AS o
    SET status = 'processing',
        attempts = o.attempts + 1,
        locked_at = now(),
        locked_by = p_worker_id,
        updated_at = now()
    FROM due
    WHERE o.id = due.id
    RETURNING o.*
  )
  SELECT
    c.id,
    c.invoice_id,
    i.order_id,
    i.provider,
    i.environment,
    i.invoice_type,
    c.attempts
  FROM claimed AS c
  JOIN public.invoices AS i ON i.id = c.invoice_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_invoice_sent(
  p_outbox_id uuid,
  p_external_id text,
  p_invoice_number text DEFAULT NULL,
  p_pdf_url text DEFAULT NULL,
  p_ubl_xml_url text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invoice_id uuid;
BEGIN
  SELECT invoice_id INTO v_invoice_id FROM public.invoice_outbox WHERE id = p_outbox_id;
  IF v_invoice_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.invoice_outbox
  SET status = 'sent',
      sent_at = now(),
      locked_at = NULL,
      locked_by = NULL,
      last_error = NULL,
      updated_at = now()
  WHERE id = p_outbox_id;

  UPDATE public.invoices
  SET status = 'sent',
      external_id = p_external_id,
      invoice_number = COALESCE(p_invoice_number, invoice_number),
      pdf_url = COALESCE(p_pdf_url, pdf_url),
      ubl_xml_url = COALESCE(p_ubl_xml_url, ubl_xml_url),
      sent_at = now(),
      error_message = NULL,
      updated_at = now()
  WHERE id = v_invoice_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_invoice_failed(
  p_outbox_id uuid,
  p_error text,
  p_max_attempts integer DEFAULT 6
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_attempts integer;
  v_invoice_id uuid;
  v_is_dead boolean;
BEGIN
  SELECT o.attempts, o.invoice_id INTO v_attempts, v_invoice_id
  FROM public.invoice_outbox AS o
  WHERE o.id = p_outbox_id
  FOR UPDATE;

  IF v_attempts IS NULL THEN
    RETURN;
  END IF;

  v_is_dead := v_attempts >= GREATEST(COALESCE(p_max_attempts, 6), 1);

  UPDATE public.invoice_outbox
  SET status = CASE WHEN v_is_dead THEN 'dead' ELSE 'failed' END,
      next_attempt_at = now() + (LEAST(power(2, v_attempts), 1800) * interval '1 second'),
      locked_at = NULL,
      locked_by = NULL,
      last_error = left(COALESCE(p_error, 'unknown'), 1000),
      updated_at = now()
  WHERE id = p_outbox_id;

  UPDATE public.invoices
  SET error_message = left(COALESCE(p_error, 'unknown'), 1000),
      status = CASE WHEN v_is_dead THEN 'error' ELSE status END,
      updated_at = now()
  WHERE id = v_invoice_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_stale_invoice_outbox(
  p_max_age interval DEFAULT interval '5 minutes'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.invoice_outbox
  SET status = 'failed',
      next_attempt_at = now(),
      locked_at = NULL,
      locked_by = NULL,
      last_error = 'stale_processing_claim',
      updated_at = now()
  WHERE status = 'processing'
    AND locked_at < now() - COALESCE(p_max_age, interval '5 minutes');

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_invoice_outbox(integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_invoice_sent(uuid, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_invoice_failed(uuid, text, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.release_stale_invoice_outbox(interval) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_invoice_outbox(integer, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_invoice_sent(uuid, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_invoice_failed(uuid, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.release_stale_invoice_outbox(interval) TO service_role;

-- ============================================================
-- 6. Poke trigger: invoice_outbox'a INSERT olunca worker'ı anında çağır
--    (20260817000002_push_outbox_instant_poke.sql ile aynı desen,
--    aynı INTERNAL_WORKER_SECRET yeniden kullanılır)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.poke_invoice_outbox_worker()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_secret text;
  v_url text;
BEGIN
  BEGIN
    v_secret := COALESCE(
      NULLIF(current_setting('app.settings.internal_worker_secret', true), ''),
      (
        SELECT vault.decrypted_secrets.decrypted_secret
        FROM vault.decrypted_secrets
        WHERE vault.decrypted_secrets.name = 'INTERNAL_WORKER_SECRET'
        ORDER BY vault.decrypted_secrets.created_at DESC
        LIMIT 1
      )
    );

    IF v_secret IS NULL OR v_secret = '' THEN
      RETURN NULL;
    END IF;

    v_url := COALESCE(
      NULLIF(current_setting('app.settings.supabase_url', true), ''),
      'https://xsbukxkgtmdyickknqzf.supabase.co'
    ) || '/functions/v1/process-invoice-outbox';

    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'x-worker-secret', v_secret,
        'Content-Type', 'application/json'
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 30000
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.poke_invoice_outbox_worker()
  FROM PUBLIC, authenticated, anon;

DROP TRIGGER IF EXISTS invoice_outbox_poke_worker ON public.invoice_outbox;
CREATE TRIGGER invoice_outbox_poke_worker
  AFTER INSERT ON public.invoice_outbox
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.poke_invoice_outbox_worker();

-- ============================================================
-- 7. system_settings — aktif sağlayıcı / ortam
-- ============================================================

INSERT INTO public.system_settings (key, value, description)
VALUES ('invoice_active_provider', 'none', 'Aktif e-fatura sağlayıcısı: none | nilvera | parasut')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.system_settings (key, value, description)
VALUES ('invoice_environment', 'test', 'E-fatura ortamı: test | live')
ON CONFLICT (key) DO NOTHING;

COMMENT ON TABLE public.invoices IS
  'Sipariş başına e-fatura/e-arşiv durum ve belge kaydı. Teslimatta taslak olarak oluşur, admin onayıyla kuyruğa alınır.';
COMMENT ON TABLE public.invoice_outbox IS
  'Admin onaylı faturaların sağlayıcı API''sine gönderim kuyruğu (idempotent, retry destekli).';

NOTIFY pgrst, 'reload schema';

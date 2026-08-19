-- ============================================================================
-- Kurye sipariş / Paket+ atama e-postaları için transactional outbox
-- ----------------------------------------------------------------------------
-- E-posta istemciden gönderilmez. İlgili domain RPC'sinin oluşturduğu güvenli
-- notification kaydı, aynı transaction içinde bu outbox'a alınır:
--   courier_order_assigned -> ilk sipariş ataması ve sipariş devri
--   package_route          -> yeni Paket+ talebinin ilk yönlendirmesi
--   new_package_request    -> Paket+ reddinden sonraki yeni yönlendirme
-- Worker, notification.user_id kullanarak yalnız ilgili kuryenin Auth e-posta
-- adresine gönderir. notification_id UNIQUE olduğundan gönderim idempotenttir.
-- ============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.courier_assignment_email_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL
    REFERENCES public.notifications(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  entity_type text NOT NULL CHECK (entity_type IN ('order', 'package')),
  entity_id uuid NOT NULL,
  notification_type text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'dead')),
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  locked_at timestamptz,
  locked_by text,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT courier_assignment_email_notification_uniq UNIQUE (notification_id)
);

CREATE INDEX IF NOT EXISTS idx_courier_assignment_email_due
  ON public.courier_assignment_email_outbox (next_attempt_at)
  WHERE status IN ('pending', 'failed');

CREATE INDEX IF NOT EXISTS idx_courier_assignment_email_processing
  ON public.courier_assignment_email_outbox (locked_at)
  WHERE status = 'processing';

ALTER TABLE public.courier_assignment_email_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.courier_assignment_email_outbox
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.courier_assignment_email_outbox TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_courier_assignment_email_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_entity_type text;
  v_entity_id uuid;
BEGIN
  IF NEW.type NOT IN (
    'courier_order_assigned',
    'package_route',
    'new_package_request'
  ) THEN
    RETURN NEW;
  END IF;

  BEGIN
    v_entity_id := NEW.entity_id::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    -- Geçersiz entity id yüzünden ana notification transaction'ını bozma.
    RETURN NEW;
  END;

  v_entity_type := CASE
    WHEN NEW.type = 'courier_order_assigned' THEN 'order'
    ELSE 'package'
  END;

  INSERT INTO public.courier_assignment_email_outbox (
    notification_id,
    courier_id,
    entity_type,
    entity_id,
    notification_type
  ) VALUES (
    NEW.id,
    NEW.user_id,
    v_entity_type,
    v_entity_id,
    NEW.type
  )
  ON CONFLICT (notification_id) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_courier_assignment_email_trigger()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS notifications_courier_assignment_email_trigger
  ON public.notifications;
CREATE TRIGGER notifications_courier_assignment_email_trigger
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.enqueue_courier_assignment_email_trigger();

CREATE OR REPLACE FUNCTION public.claim_courier_assignment_emails(
  p_limit integer DEFAULT 25,
  p_worker_id text DEFAULT 'email-worker'
)
RETURNS TABLE (
  outbox_id uuid,
  notification_id uuid,
  courier_id uuid,
  entity_type text,
  entity_id uuid,
  notification_type text,
  attempt_number integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT o.id
    FROM public.courier_assignment_email_outbox AS o
    WHERE o.status IN ('pending', 'failed')
      AND o.next_attempt_at <= now()
    ORDER BY o.next_attempt_at, o.created_at
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.courier_assignment_email_outbox AS o
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
    c.notification_id,
    c.courier_id,
    c.entity_type,
    c.entity_id,
    c.notification_type,
    c.attempts
  FROM claimed AS c;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_courier_assignment_email_sent(
  p_outbox_id uuid
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.courier_assignment_email_outbox
  SET status = 'sent',
      sent_at = now(),
      locked_at = NULL,
      locked_by = NULL,
      last_error = NULL,
      updated_at = now()
  WHERE id = p_outbox_id;
$$;

CREATE OR REPLACE FUNCTION public.mark_courier_assignment_email_failed(
  p_outbox_id uuid,
  p_error text,
  p_max_attempts integer DEFAULT 8
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_attempts integer;
BEGIN
  SELECT o.attempts INTO v_attempts
  FROM public.courier_assignment_email_outbox AS o
  WHERE o.id = p_outbox_id
  FOR UPDATE;

  IF v_attempts IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.courier_assignment_email_outbox
  SET status = CASE
        WHEN v_attempts >= GREATEST(COALESCE(p_max_attempts, 8), 1)
          THEN 'dead'
        ELSE 'failed'
      END,
      next_attempt_at = now() + (
        LEAST(power(2, v_attempts), 1800) * interval '1 second'
      ),
      locked_at = NULL,
      locked_by = NULL,
      last_error = left(COALESCE(p_error, 'unknown'), 1000),
      updated_at = now()
  WHERE id = p_outbox_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_stale_courier_assignment_emails(
  p_max_age interval DEFAULT interval '5 minutes'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.courier_assignment_email_outbox
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

REVOKE ALL ON FUNCTION public.claim_courier_assignment_emails(integer, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_courier_assignment_email_sent(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_courier_assignment_email_failed(uuid, text, integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.release_stale_courier_assignment_emails(interval)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_courier_assignment_emails(integer, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_courier_assignment_email_sent(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_courier_assignment_email_failed(uuid, text, integer)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.release_stale_courier_assignment_emails(interval)
  TO service_role;

COMMENT ON TABLE public.courier_assignment_email_outbox IS
  'Sipariş ve Paket+ ilk atama/yönlendirme ile ret sonrası devir e-postaları için idempotent, retry destekli sunucu outbox''ı.';

NOTIFY pgrst, 'reload schema';


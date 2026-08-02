-- =============================================================================
-- 2026-08-02 — Push outbox worker için pg_cron scheduler
-- -----------------------------------------------------------------------------
-- SQL Editor'de manuel çalıştırılır.
-- Önce: supabase secrets set INTERNAL_WORKER_SECRET=... ile Edge Function'a
--        set edildi. Aynı değer bu SQL'de hard-coded olur (script tek kullanımlık).
--        Production için: Supabase Dashboard → Database → Settings →
--        Custom Postgres Config içine
--        app.settings.internal_worker_secret = '...' ekleyerek bu SQL'i
--        generic hale getirebilirsin.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
DECLARE
  v_worker_secret TEXT := current_setting('app.settings.internal_worker_secret', true);
  v_supabase_url  TEXT := current_setting('app.settings.supabase_url', true);
BEGIN
  -- app.settings üzerinden gelmediyse kullanıcıya net hata göster.
  IF v_worker_secret IS NULL OR v_worker_secret = '' THEN
    RAISE EXCEPTION
      'app.settings.internal_worker_secret tanımlı değil. '
      'Bu SQL''i çalıştırmadan önce Supabase Dashboard → Database → Settings → '
      'Custom Postgres Config içine '
      'app.settings.internal_worker_secret = ''<INTERNAL_WORKER_SECRET>'' ekleyin.';
  END IF;
  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    v_supabase_url := 'https://xsbukxkgtmdyickknqzf.supabase.co';
  END IF;

  -- Eski scheduler job varsa kaldır (idempotent).
  PERFORM cron.unschedule('process-notification-outbox-every-minute')
    WHERE EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'process-notification-outbox-every-minute'
    );

  -- Her dakika başı worker'ı çağır.
  PERFORM cron.schedule(
    'process-notification-outbox-every-minute',
    '* * * * *',
    format(
      $cron$
      SELECT net.http_post(
        url     := %L,
        headers := jsonb_build_object(
          'x-worker-secret', %L,
          'Content-Type',    'application/json'
        ),
        body    := '{}'::jsonb,
        timeout_milliseconds := 30000
      );
      $cron$,
      v_supabase_url || '/functions/v1/process-notification-outbox',
      v_worker_secret
    )
  );
END
$$;

-- Scheduler kurulduktan sonra job'u doğrula
SELECT jobname, schedule, active
  FROM cron.job
 WHERE jobname = 'process-notification-outbox-every-minute';

-- ============================================================================
-- Kurye atama e-posta outbox worker scheduler
-- ----------------------------------------------------------------------------
-- Önkoşullar:
--   1) process-courier-assignment-emails Edge Function deploy edilmiş olmalı.
--   2) Edge Function secret: INTERNAL_WORKER_SECRET ve RESEND_API_KEY.
--   3) Worker secret veritabanında aşağıdaki kaynaklardan birinde bulunmalı:
--      a) app.settings.internal_worker_secret = aynı INTERNAL_WORKER_SECRET
--      b) Supabase Vault'ta adı INTERNAL_WORKER_SECRET olan secret
--      app.settings.supabase_url isteğe bağlıdır (yoksa proje fallback'i).
--      Vault kaydı doğrudan vault.secrets INSERT ile oluşturulmamalıdır;
--      Dashboard Vault ekranı veya vault.create_secret(...) kullanılmalıdır.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

DO $$
DECLARE
  v_worker_secret text := current_setting(
    'app.settings.internal_worker_secret', true
  );
  v_supabase_url text := current_setting('app.settings.supabase_url', true);
BEGIN
  -- Managed Supabase projelerinde Custom Postgres Config her planda/rolde
  -- değiştirilemeyebilir. Bu nedenle aynı secret için Vault güvenli fallback'tir.
  IF (v_worker_secret IS NULL OR v_worker_secret = '')
     AND to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
    EXECUTE $vault$
      SELECT decrypted_secret
      FROM vault.decrypted_secrets
      WHERE name IN (
        'COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET',
        'INTERNAL_WORKER_SECRET'
      )
      ORDER BY
        CASE
          WHEN name = 'COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET' THEN 0
          ELSE 1
        END,
        created_at DESC
      LIMIT 1
    $vault$
    INTO v_worker_secret;
  END IF;

  IF v_worker_secret IS NULL OR v_worker_secret = '' THEN
    RAISE EXCEPTION
      'INTERNAL_WORKER_SECRET veritabanında bulunamadı. Custom Postgres Config içine app.settings.internal_worker_secret ekleyin veya Supabase Vault''ta INTERNAL_WORKER_SECRET adlı secret oluşturun.';
  END IF;

  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    v_supabase_url := 'https://xsbukxkgtmdyickknqzf.supabase.co';
  END IF;

  PERFORM cron.unschedule('process-courier-assignment-emails-every-minute')
  WHERE EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'process-courier-assignment-emails-every-minute'
  );

  PERFORM cron.schedule(
    'process-courier-assignment-emails-every-minute',
    '* * * * *',
    $cron$
      SELECT net.http_post(
        url := COALESCE(
          NULLIF(current_setting('app.settings.supabase_url', true), ''),
          'https://xsbukxkgtmdyickknqzf.supabase.co'
        ) || '/functions/v1/process-courier-assignment-emails',
        headers := jsonb_build_object(
          'x-worker-secret', COALESCE(
            NULLIF(current_setting(
              'app.settings.internal_worker_secret', true
            ), ''),
            (
              SELECT decrypted_secret
              FROM vault.decrypted_secrets
              WHERE name IN (
                'COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET',
                'INTERNAL_WORKER_SECRET'
              )
              ORDER BY
                CASE
                  WHEN name = 'COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET' THEN 0
                  ELSE 1
                END,
                created_at DESC
              LIMIT 1
            )
          ),
          'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 30000
      );
    $cron$
  );
END;
$$;

SELECT jobname, schedule, active
FROM cron.job
WHERE jobname = 'process-courier-assignment-emails-every-minute';


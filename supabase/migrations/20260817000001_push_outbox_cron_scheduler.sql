-- ============================================================================
-- Push notification outbox worker scheduler (2026-08-14)
-- ----------------------------------------------------------------------------
-- GEÇMİŞ: 20260802000004 bu cron'u yalnızca
-- app.settings.internal_worker_secret custom config'i varsa kuruyordu.
-- Custom Postgres Config plan/rol kısıtları nedeniyle hiç ayarlanamadığı için
-- job hiç oluşmadı ve push bildirimler outbox'ta birikti (bkz.
-- diagnostics/20260807_push_pipeline_health_check_v3.sql özet satırı).
--
-- Bu migration 20260812000003 (kurye e-posta cron'u) ile aynı deseni kullanır:
-- secret önce custom config'den, yoksa Supabase Vault'tan çözülür.
-- Vault'ta COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET ve INTERNAL_WORKER_SECRET
-- bulunuyor; edge env INTERNAL_WORKER_SECRET ile kanıtlanmış eşleşen değer
-- COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET olduğu için COALESCE sırası
-- önce onu seçer. Ayrıca vault'taki INTERNAL_WORKER_SECRET değerini
-- eşleşen değerle senkronlar (sonraki fallback'ler tutarlı kalır).
--
-- Önkoşullar:
--   1) process-notification-outbox Edge Function deploy edilmiş olmalı.
--   2) Edge secret'lar: INTERNAL_WORKER_SECRET, FIREBASE_SERVICE_ACCOUNT.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

DO $$
DECLARE
  v_worker_secret text := current_setting(
    'app.settings.internal_worker_secret', true
  );
  v_vault_courier_secret text;
  v_supabase_url text := current_setting('app.settings.supabase_url', true);
BEGIN
  -- 1) Custom config yoksa Vault'tan çöz (kurye cron deseni ile aynı).
  IF (v_worker_secret IS NULL OR v_worker_secret = '')
     AND to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
    EXECUTE $vault$
      SELECT decrypted_secret
      FROM vault.decrypted_secrets
      WHERE name = 'COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET'
      ORDER BY created_at DESC
      LIMIT 1
    $vault$
    INTO v_worker_secret;
  END IF;

  IF v_worker_secret IS NULL OR v_worker_secret = '' THEN
    EXECUTE $vault$
      SELECT decrypted_secret
      FROM vault.decrypted_secrets
      WHERE name = 'INTERNAL_WORKER_SECRET'
      ORDER BY created_at DESC
      LIMIT 1
    $vault$
    INTO v_worker_secret;
  END IF;

  IF v_worker_secret IS NULL OR v_worker_secret = '' THEN
    RAISE EXCEPTION
      'Worker secret bulunamadı. Custom Postgres Config''e '
      'app.settings.internal_worker_secret ekleyin veya Supabase Vault''ta '
      'COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET / INTERNAL_WORKER_SECRET '
      'oluşturun.';
  END IF;

  -- 2) Vault'taki INTERNAL_WORKER_SECRET değerini çalışan değerle senkronla
  --    (best-effort; başarısızlık kurulumu engellemez).
  BEGIN
    IF to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
      SELECT decrypted_secret
        INTO v_vault_courier_secret
        FROM vault.decrypted_secrets
        WHERE name = 'COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET'
        ORDER BY created_at DESC
        LIMIT 1;

      IF v_vault_courier_secret IS NOT NULL THEN
        PERFORM vault.create_secret(
          v_vault_courier_secret,
          'INTERNAL_WORKER_SECRET'
        );
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Vault INTERNAL_WORKER_SECRET senkronu atlandı: %', SQLERRM;
  END;

  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    v_supabase_url := 'https://xsbukxkgtmdyickknqzf.supabase.co';
  END IF;

  -- 3) Eski job varsa kaldır (idempotent).
  PERFORM cron.unschedule('process-notification-outbox-every-minute')
  WHERE EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'process-notification-outbox-every-minute'
  );

  -- 4) Job'ı kur. Header değeri HER ÇALIŞMADA yeniden çözülür; Vault'ta
  --    değer değişirse job'ı yeniden kurmak gerekmez.
  PERFORM cron.schedule(
    'process-notification-outbox-every-minute',
    '* * * * *',
    $cron$
      SELECT net.http_post(
        url := COALESCE(
          NULLIF(current_setting('app.settings.supabase_url', true), ''),
          'https://xsbukxkgtmdyickknqzf.supabase.co'
        ) || '/functions/v1/process-notification-outbox',
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
WHERE jobname = 'process-notification-outbox-every-minute';

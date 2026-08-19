-- ============================================================================
-- Canlı kurye atama görünürlüğü ve e-posta scheduler onarımı
-- ----------------------------------------------------------------------------
-- 1) Eski uuid parametreli RPC overload'ları PostgREST sözleşmesinde kaldığı
--    için istemcinin kullandığı parametresiz güvenli RPC'lerle çakışıyordu.
--    Parametreli, PII sızdıran eski overload'lar kaldırılır.
-- 2) Son atamalarda notification/outbox oluştuğu halde cron worker outbox'ı
--    claim etmedi. Job, Vault secret'ını her çalışmada güvenli şekilde okuyup
--    Edge Function'a iletecek biçimde yeniden kurulur. Vault'taki değer Edge
--    Function INTERNAL_WORKER_SECRET değeriyle birebir aynı olmalıdır. Secret
--    cron.job.command içine düz metin olarak gömülmez.
-- ============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- Eski PII döndüren ve istemcinin artık kullanmadığı overload'ları kaldır.
DROP FUNCTION IF EXISTS public.get_available_orders_for_courier(uuid);
DROP FUNCTION IF EXISTS public.get_courier_active_orders(uuid);

-- Parametresiz güvenli sözleşmelerin yetkilerini deterministik yeniden kur.
REVOKE ALL ON FUNCTION public.get_available_orders_for_courier()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_available_orders_for_courier()
  TO authenticated;

REVOKE ALL ON FUNCTION public.get_courier_active_orders()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_active_orders()
  TO authenticated;

-- Önceden elle claim edilip processing'de kalmış işleri yeniden alınabilir yap.
SELECT public.release_stale_courier_assignment_emails(interval '0 seconds');

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

DO $$
BEGIN
  IF to_regclass('vault.decrypted_secrets') IS NULL THEN
    RAISE EXCEPTION
      'Supabase Vault bulunamadı. INTERNAL_WORKER_SECRET Vault secret''ı gerekli.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM vault.decrypted_secrets
    WHERE name IN (
      'COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET',
      'INTERNAL_WORKER_SECRET'
    )
      AND NULLIF(decrypted_secret, '') IS NOT NULL
  ) THEN
    RAISE EXCEPTION
      'Vault içinde COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET veya INTERNAL_WORKER_SECRET bulunamadı.';
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
      url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/process-courier-assignment-emails',
      headers := jsonb_build_object(
        'x-worker-secret', (
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

NOTIFY pgrst, 'reload schema';


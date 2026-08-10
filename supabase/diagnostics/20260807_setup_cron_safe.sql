-- =============================================================================
-- 2026-08-07 — Cron scheduler kurulumu (güvenli versiyon, fallback destekli)
-- -----------------------------------------------------------------------------
-- AMAÇ: process-notification-outbox worker'ı her dakika çağıracak
--       pg_cron job'ı kurmak.
--
-- ÖN-KOŞULLAR:
--   1) Edge Function'da process-notification-outbox deploy edilmiş olmalı
--      (supabase functions deploy process-notification-outbox).
--   2) Edge Function secret'ları tanımlı olmalı:
--      supabase secrets set INTERNAL_WORKER_SECRET=<SECRET>
--      supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
--
-- SECRET KAYNAĞI (öncelik sırası):
--   A) app.settings.internal_worker_secret (Postgres custom config — önerilen)
--   B) DO blok parametresi: \set secret '<SECRET>'  (psql/CLI kullanıcıları için)
--
-- ÇALIŞTIRMA:
--   Yol A) Önce Dashboard → Database → Settings → Custom Postgres Config
--          içine app.settings.internal_worker_secret = '<SECRET>' ekle, sonra
--          bu SQL'i SQL Editor'den çalıştır.
--
--   Yol B) Tek seferde: psql veya supabase db shell ile:
--          \set secret 'gizli_secret_buraya'
--          \i supabase/diagnostics/20260807_setup_cron_safe.sql
--          (Bu durumda SQL otomatik custom config'e de yazacak ki sonraki
--           oturumlarda Yol A kullanılabilsin.)
--
--   Yol C) SQL Editor'de açılan pencerede, dosyanın EN ALTINDAKİ
--          "MANUEL SETUP (Yol C)" bölümünü gör; oradaki tek satırlık
--          `SELECT set_config(...)` çağrısıyla bu oturum için secret
--          tanımlanabilir, ardından cron kurulumu yeniden çalıştırılabilir.
-- =============================================================================

-- 1) pg_cron extension kurulu değilse kur
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2) Eski job varsa kaldır (idempotent)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname='process-notification-outbox-every-minute') THEN
    PERFORM cron.unschedule('process-notification-outbox-every-minute');
    RAISE NOTICE 'Eski cron job kaldırıldı';
  END IF;
END $$;

-- 3) Secret'ı belirle (öncelik sırası: custom config > psql GUC > "")
DO $resolve$
DECLARE
  v_secret_from_config TEXT := NULLIF(
    current_setting('app.settings.internal_worker_secret', true), ''
  );
  v_secret_from_guc    TEXT := NULLIF(
    current_setting('cron.setup_secret', true), ''
  );
  v_secret             TEXT;
BEGIN
  v_secret := COALESCE(v_secret_from_config, v_secret_from_guc);

  IF v_secret IS NULL THEN
    RAISE NOTICE
      '⏭️  Cron job kurulumu atlandı: secret tanımsız. '
      'Üç yol var: '
      '(A) Dashboard → Database → Settings → Custom Postgres Config → '
      'app.settings.internal_worker_secret = ''<SECRET>'' ekleyip tekrar çalıştır; '
      '(B) psql/CLI: \set secret ''<SECRET>'' sonra \i bu_dosya; '
      '(C) SQL Editor: dosyanın en altındaki SELECT set_config(...) satırını '
      'çalıştır, ardından BÖLÜM 4''ü tekrar çalıştır.';
    -- Yine de yarı-idempotent kal: scheduled_jobs tablosu boş bırakılır.
    RETURN;
  END IF;

  -- Secret'ı custom config'e de yaz (kalıcı olsun, sonraki oturumlar için)
  EXECUTE format('ALTER DATABASE %I SET app.settings.internal_worker_secret = %L',
    current_database(), v_secret);
  RAISE NOTICE '✅ app.settings.internal_worker_secret custom config''e yazıldı.';

  -- 4) Cron job'ı kur
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
      COALESCE(NULLIF(current_setting('app.settings.supabase_url', true), ''),
               'https://xsbukxkgtmdyickknqzf.supabase.co')
        || '/functions/v1/process-notification-outbox',
      v_secret
    )
  );

  RAISE NOTICE '✅ Cron job kuruldu.';
END
$resolve$;

-- 5) Doğrulama
SELECT
  'cron job durumu' AS kontrol,
  jobname, schedule, active,
  to_char(last_start_time, 'YYYY-MM-DD HH24:MI:SS') AS son_calisma,
  to_char(next_run, 'YYYY-MM-DD HH24:MI:SS') AS sonraki_calisma
FROM cron.job
WHERE jobname='process-notification-outbox-every-minute';

-- 6) İlk claim'i hemen tetikle (worker'ı beklemeden, opsiyonel)
DO $fire$
DECLARE
  v_secret TEXT := COALESCE(
    NULLIF(current_setting('app.settings.internal_worker_secret', true), ''),
    NULLIF(current_setting('cron.setup_secret', true), '')
  );
  v_url    TEXT := COALESCE(
    NULLIF(current_setting('app.settings.supabase_url', true), ''),
    'https://xsbukxkgtmdyickknqzf.supabase.co'
  );
  v_req_id BIGINT;
BEGIN
  IF v_secret IS NULL THEN
    RAISE NOTICE '⏭️  Manuel tetikleme atlandı (secret tanımsız)';
    RETURN;
  END IF;

  BEGIN
    SELECT net.http_post(
      url     := v_url || '/functions/v1/process-notification-outbox',
      headers := jsonb_build_object(
        'x-worker-secret', v_secret,
        'Content-Type',    'application/json'
      ),
      body    := '{}'::jsonb,
      timeout_milliseconds := 30000
    ) INTO v_req_id;
    RAISE NOTICE '✅ Manuel tetikleme yapıldı. request_id=%  — Edge Function loglarından sonucu kontrol et.', v_req_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '⚠️  Manuel tetikleme başarısız: %. pg_net extension kurulu değilse Dashboard → Database → Extensions → pg_net etkinleştir.', SQLERRM;
  END;
END
$fire$;

-- =============================================================================
-- MANUEL SETUP (Yol C) — SQL Editor kullanıcıları için
-- =============================================================================
-- Aşağıdaki satırı kopyala, SECRET kısmını kendi secret'ınla değiştir,
-- SQL Editor'de tek başına çalıştır. Bu sadece bu oturum için geçerli
-- olur; kalıcı olması için yine de Dashboard Custom Postgres Config'e
-- veya yukarıdaki BÖLÜM 3'teki `ALTER DATABASE` ile eklenmeli.
--
-- SELECT set_config('app.settings.internal_worker_secret', 'BURAYA_SECRET_YAPISTIR', false);
--
-- Ardından BÖLÜM 3 + 4'ü (DO $resolve$ ... $resolve$;) tekrar çalıştır.
-- =============================================================================

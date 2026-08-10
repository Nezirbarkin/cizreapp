-- =============================================================================
-- 2026-08-07 — Tek adımda cron kurulumu (ALTER DATABASE yetkisi gerektirmez)
-- -----------------------------------------------------------------------------
-- AMAÇ: app.settings.internal_worker_secret Postgres custom config'e
--       ALTER DATABASE ile yazılamadığında (managed Supabase'te yetki yok),
--       bu SQL içinde GUC olarak set edilip cron hemen kurulabilir.
--
-- YÖNTEM:
--   1) SQL Editor'de bu dosyayı aç
--   2) AŞAĞIDAKİ "SETUP_SECRET_DEĞİŞKENİ" kısmına kendi secret'ını yaz
--      (örn. a3f5e9c1b2d4e6f8a3f5e9c1b2d4e6f8a3f5e9c1b2d4e6f8a3f5e9c1b2d4e6f8)
--   3) Tüm dosyayı çalıştır
--   4) Cron kurulur ve bir sonraki dakikada worker çalışmaya başlar
--
-- ⚠️  Bu yöntemde secret SADECE bu SQL oturumunda GUC olarak yaşar.
--    Kalıcı olması için Yöntem 1 (Dashboard Custom Postgres Config) veya
--    service_role ile çalışan bir migration kullanmak gerekir. Ancak
--    cron job'ı bir kez kurulduktan sonra secret her dakika aynı
--    değerle kullanılacağı için GUC'un kalıcı olması gerekmez — secret
--    format() içine gömülür.
-- =============================================================================

-- 1) pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2) Eski job'ı kaldır
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname='process-notification-outbox-every-minute') THEN
    PERFORM cron.unschedule('process-notification-outbox-every-minute');
    RAISE NOTICE 'Eski cron job kaldırıldı';
  END IF;
END $$;

-- 3) Secret'ı bu oturum için GUC olarak set et ve cron'u kur
--    ALTER DATABASE yetkisi olmadığı için DO $$ içinde değişken olarak
--    gömüyoruz; bu şekilde service-role olmadan da çalışır.
DO $$
DECLARE
  -- ╔══════════════════════════════════════════════════════════════╗
  -- ║  AŞAĞIDAKİ SATIRA KENDİ SECRET'INIZI YAPISTIRIN            ║
  -- ║  ADIM 5'te Edge Function env'inde de AYNI secret'ı kullanın  ║
  -- ╚══════════════════════════════════════════════════════════════╝
  v_secret TEXT := 'BURAYA_SECRET_YAPISTIR';

  v_url    TEXT := COALESCE(
    NULLIF(current_setting('app.settings.supabase_url', true), ''),
    'https://xsbukxkgtmdyickknqzf.supabase.co'
  );
BEGIN
  IF v_secret IS NULL OR v_secret = '' OR v_secret = 'BURAYA_SECRET_YAPISTIR' THEN
    RAISE EXCEPTION
      'Lütfen bu SQL dosyasındaki ''BURAYA_SECRET_YAPISTIR'' placeholder''ını '
      'kendi secret''ınızla değiştirin. ADIM 5''te Edge Function env''inde '
      'de AYNI secret''ı kullanacaksınız.';
  END IF;

  -- GUC olarak set et (bu oturum için)
  PERFORM set_config('app.settings.internal_worker_secret', v_secret, false);

  RAISE NOTICE '✅ Secret GUC olarak ayarlandı (uzunluk: % karakter)', length(v_secret);

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
      v_url || '/functions/v1/process-notification-outbox',
      v_secret
    )
  );

  RAISE NOTICE '✅ Cron job kuruldu: process-notification-outbox-every-minute';
  RAISE NOTICE '📍 URL: %', v_url;
END
$$;

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
  v_secret TEXT := current_setting('app.settings.internal_worker_secret', true);
  v_url    TEXT := COALESCE(
    NULLIF(current_setting('app.settings.supabase_url', true), ''),
    'https://xsbukxkgtmdyickknqzf.supabase.co'
  );
  v_req_id BIGINT;
BEGIN
  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE NOTICE '⏭️  Manuel tetikleme atlandı (secret GUC''ta yok)';
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
    RAISE NOTICE '✅ Manuel tetikleme yapıldı. request_id=% — Edge Function loglarından sonucu kontrol et.', v_req_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '⚠️  Manuel tetikleme başarısız: %. pg_net extension kurulu değilse Dashboard → Database → Extensions → pg_net etkinleştir.', SQLERRM;
  END;
END
$fire$;

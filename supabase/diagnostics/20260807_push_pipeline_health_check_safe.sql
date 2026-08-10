-- =============================================================================
-- 2026-08-07 — Push notification pipeline sağlık kontrolü (güvenli versiyon)
-- -----------------------------------------------------------------------------
-- AMAÇ: Neden push notification gelmediğini tespit etmek için hızlı bir
--       durum tespiti. Supabase SQL Editor'de çalıştırılır; veri yazmaz.
--
-- BU VERSİYON outbox tablosu/nesnesi yoksa bile hata vermez; her kontrol
-- kendi varlığını doğrular ve ❌ ise açıklayıcı mesaj verir.
--
-- KULLANIM:
--   1) Supabase Dashboard → SQL Editor
--   2) Bu dosyanın içeriğini yapıştır
--   3) Çalıştır
--   4) Çıktıdaki ❌ işaretli satırlar sorunun yerini gösterir
-- =============================================================================

-- ============================================================================
-- A) Outbox tablosu ve trigger durumu
-- ============================================================================

-- A1) notification_outbox tablosu mevcut mu?
SELECT
  'A1) notification_outbox tablosu' AS kontrol,
  CASE
    WHEN to_regclass('public.notification_outbox') IS NOT NULL
    THEN '✅ mevcut'
    ELSE '❌ YOK — 20260802000003 migration canlıda uygulanmamış. Uygula: supabase db push veya SQL Editor''den 20260802000003_secure_push_notification_pipeline.sql + 20260802000004_push_outbox_cron_scheduler.sql çalıştır.'
  END AS durum;

-- A2) Yeni trigger bağlı mı? (outbox tablosu varsa kontrol edilir)
SELECT
  'A2) notifications_outbox_trigger (yeni)' AS kontrol,
  CASE
    WHEN to_regclass('public.notification_outbox') IS NULL THEN '⏭️  atlandı (A1 ❌)'
    WHEN EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname='notifications_outbox_trigger'
        AND tgrelid='public.notifications'::regclass
    ) THEN '✅ bağlı'
    ELSE '❌ YOK — push tetiklenmiyor'
  END AS durum;

-- A3) Eski trigger kaldırılmış mı?
SELECT
  'A3) notifications_push_trigger (eski, kaldırılmalı)' AS kontrol,
  CASE
    WHEN NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname='notifications_push_trigger'
        AND tgrelid='public.notifications'::regclass
    ) THEN '✅ kaldırıldı'
    ELSE '❌ hâlâ bağlı — çift push riski!'
  END AS durum;

-- ============================================================================
-- B) Eski net.http_post trigger'ları kaldırılmış mı?
-- ============================================================================

SELECT
  'B) notify_price_drops net.http_post içeriyor mu?' AS kontrol,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname='public' AND p.proname='notify_price_drops'
        AND p.prosrc ILIKE '%net.http_post%'
    ) THEN '❌ net.http_post hâlâ var — eski migration'
    ELSE '✅ temiz (yeni tanım net.http_post KULLANMAZ)'
  END AS durum;

-- ============================================================================
-- C) pg_cron kurulumu
-- ============================================================================

SELECT
  'C1) pg_cron extension' AS kontrol,
  CASE
    WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
    THEN '✅ mevcut'
    ELSE '❌ pg_cron kurulu değil. Supabase Dashboard → Database → Extensions → pg_cron etkinleştir.'
  END AS durum;

SELECT
  'C2) process-notification-outbox cron job' AS kontrol,
  CASE
    WHEN NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
    THEN '⏭️  atlandı (C1 ❌)'
    WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname='process-notification-outbox-every-minute')
    THEN '✅ kurulu'
    ELSE '❌ KURULMAMIŞ — push hiç gelmez! 20260802000004 uygulanmamış veya app.settings.internal_worker_secret tanımsız.'
  END AS durum;

-- ============================================================================
-- D) Outbox RPC'leri (outbox tablosu varsa kontrol edilir)
-- ============================================================================

SELECT
  'D) ' || p.proname AS kontrol,
  CASE
    WHEN to_regclass('public.notification_outbox') IS NULL THEN '⏭️  atlandı (A1 ❌)'
    WHEN has_function_privilege('service_role', p.oid::regprocedure, 'EXECUTE')
    THEN '✅ service_role erişebilir'
    ELSE '❌ service_role erişemez'
  END AS durum
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'enqueue_notification_outbox',
    'claim_notification_outbox',
    'mark_outbox_sent',
    'mark_outbox_failed',
    'release_stale_outbox',
    'admin_send_personal_notification',
    'admin_broadcast_notification',
    'share_post_with_user',
    'add_notification'
  )
ORDER BY p.proname;

-- ============================================================================
-- E) Secret env (Postgres custom config)
-- ============================================================================

SELECT
  'E) app.settings.internal_worker_secret (Postgres custom config)' AS kontrol,
  CASE
    WHEN current_setting('app.settings.internal_worker_secret', true) IS NOT NULL
     AND current_setting('app.settings.internal_worker_secret', true) <> ''
    THEN '✅ Postgres custom config''te ayarlı'
    ELSE '⚠️  Postgres custom config''te yok. Supabase Dashboard → Database → Settings → Custom Postgres Config → app.settings.internal_worker_secret = ''<SECRET>'''
  END AS durum;

-- ============================================================================
-- F) Outbox durumu (sadece tablo varsa)
-- ============================================================================

SELECT
  'F) Outbox istatistikleri (son 24 saat)' AS kontrol,
  to_char(NOW(), 'YYYY-MM-DD HH24:MI') AS zaman,
  CASE WHEN to_regclass('public.notification_outbox') IS NULL THEN '⏭️  atlandı (A1 ❌)' END AS durum;

DO $$
BEGIN
  IF to_regclass('public.notification_outbox') IS NOT NULL THEN
    RAISE NOTICE 'Outbox istatistikleri:';
    RETURN QUERY
      SELECT
        'F) ' || status AS kontrol,
        COUNT(*)::text AS adet,
        MIN(next_attempt_at)::text AS en_eski
      FROM public.notification_outbox
      WHERE created_at > NOW() - INTERVAL '24 hours'
      GROUP BY status
      ORDER BY status;
  END IF;
END $$;

-- ============================================================================
-- G) Dead/Failed outbox detay (sadece tablo varsa)
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.notification_outbox') IS NOT NULL THEN
    RAISE NOTICE 'Dead/Failed outbox detay (son 24 saat, max 10):';
    RETURN QUERY
      SELECT
        'G) ' || status AS kontrol,
        left(last_error, 200) AS son_hata,
        to_char(next_attempt_at, 'YYYY-MM-DD HH24:MI:SS') AS sonraki_deneme
      FROM public.notification_outbox
      WHERE status IN ('dead','failed')
        AND created_at > NOW() - INTERVAL '24 hours'
      ORDER BY created_at DESC
      LIMIT 10;
  ELSE
    RAISE NOTICE 'G) atlandı (A1 ❌)';
  END IF;
END $$;

-- ============================================================================
-- H) Pending birikim (sadece tablo varsa)
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.notification_outbox') IS NOT NULL THEN
    RAISE NOTICE 'H) Pending birikim (son 1 saat):';
    RETURN QUERY
      SELECT
        'H) status=' || status AS kontrol,
        COUNT(*)::text AS adet,
        CASE
          WHEN MAX(created_at) IS NULL THEN '-'
          ELSE to_char(EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))/60, 'FM999990.0') || ' dk'
        END AS en_eski
      FROM public.notification_outbox
      WHERE created_at > NOW() - INTERVAL '1 hour'
      GROUP BY status
      ORDER BY status;
  ELSE
    RAISE NOTICE 'H) atlandı (A1 ❌)';
  END IF;
END $$;

-- ============================================================================
-- I) FCM token kayıtlı kullanıcı sayısı
-- ============================================================================

DO $$
DECLARE
  v_tokenli   BIGINT;
  v_tokensiz  BIGINT;
  v_toplam    BIGINT;
BEGIN
  -- 20260803000006 sonrası profiles SELECT grant kaldırıldı; sütun
  -- bazlı erişimle fcm_token doğrudan okunamaz. Bu yüzden service_role
  -- olmayan bağlamda hata alabilir. Try/catch ile sarıyoruz.
  BEGIN
    SELECT
      COUNT(*) FILTER (WHERE fcm_token IS NOT NULL AND fcm_token <> ''),
      COUNT(*) FILTER (WHERE fcm_token IS NULL OR fcm_token = ''),
      COUNT(*)
    INTO v_tokenli, v_tokensiz, v_toplam
    FROM public.profiles;
    RAISE NOTICE 'I) FCM token kayıtlı kullanıcı: tokenli=%, tokensiz=%, toplam=%',
      v_tokenli, v_tokensiz, v_toplam;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'I) FCM token istatistiği alınamadı (%). Muhtemelen 20260803000006 sonrası SELECT grant kısıtlı. Dashboard > Table Editor > profiles üzerinden kontrol et.', SQLERRM;
  END;
END $$;

-- ============================================================================
-- J) Bildirim tipleri (son 24 saat)
-- ============================================================================

SELECT
  'J) ' || COALESCE(type, '(null)') AS kontrol,
  COUNT(*)::text AS adet
FROM public.notifications
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY type
ORDER BY COUNT(*) DESC;

-- ============================================================================
-- K) Worker secret ayarı (Postgres custom config) — cron için zorunlu
-- ============================================================================

SELECT
  'K) app.settings.supabase_url (cron için)' AS kontrol,
  CASE
    WHEN current_setting('app.settings.supabase_url', true) IS NOT NULL
     AND current_setting('app.settings.supabase_url', true) <> ''
    THEN '✅ ayarlı: ' || current_setting('app.settings.supabase_url', true)
    ELSE '⚠️  ayarlı değil. Default (https://xsbukxkgtmdyickknqzf.supabase.co) kullanılır. Custom ayarlamak için app.settings.supabase_url = ''<URL>'''
  END AS durum;

-- ============================================================================
-- L) Edge Function env'leri (Deno.env üzerinden okunur, burada göremeyiz;
--    Edge Function loglarından kontrol edilecek.)
-- ============================================================================

SELECT
  'L) INTERNAL_WORKER_SECRET (Edge Function env)' AS kontrol,
  '⚠️  Supabase Dashboard → Edge Functions → process-notification-outbox → Secrets. Yoksa: supabase secrets set INTERNAL_WORKER_SECRET=<SECRET> ve redeploy.' AS durum;

SELECT
  'L) FIREBASE_SERVICE_ACCOUNT (Edge Function env)' AS kontrol,
  '⚠️  Supabase Dashboard → Edge Functions → process-notification-outbox → Secrets. JSON service account dosyasının tamamı (newlines dahil). Yoksa: supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)" ve redeploy.' AS durum;

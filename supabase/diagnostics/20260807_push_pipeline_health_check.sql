-- =============================================================================
-- 2026-08-07 — Push notification pipeline sağlık kontrolü (diagnostic)
-- -----------------------------------------------------------------------------
-- AMAÇ: Neden push notification gelmediğini tespit etmek için hızlı bir
--       durum tespiti. Supabase SQL Editor'de çalıştırılır; veri yazmaz
--       (yalnızca SELECT ve pg_catalog sorguları).
--
-- KULLANIM:
--   1) Supabase Dashboard → SQL Editor
--   2) Bu dosyanın içeriğini yapıştır
--   3) Çıktıdaki ❌ işaretli satırlar sorunun yerini gösterir
--
-- Canlı push hattının sağlıklı olması için aşağıdaki TÜM kontroller
-- ✅ olmalıdır. Herhangi biri ❌ ise push gelmiyor olabilir.
-- =============================================================================

-- 1) notification_outbox tablosu mevcut mu?
SELECT
  'A1) notification_outbox tablosu' AS kontrol,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname='public' AND tablename='notification_outbox'
  ) THEN '✅ mevcut' ELSE '❌ YOK — 20260802000003 migration uygulanmamış' END AS durum;

-- 2) Yeni trigger bağlı mı? (eski kaldırılmış mı?)
SELECT
  'A2) notifications_outbox_trigger' AS kontrol,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname='notifications_outbox_trigger'
      AND tgrelid='public.notifications'::regclass
  ) THEN '✅ bağlı' ELSE '❌ YOK — push tetiklenmiyor' END AS durum;

SELECT
  'A3) notifications_push_trigger (eski, kaldırılmalı)' AS kontrol,
  CASE WHEN NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname='notifications_push_trigger'
      AND tgrelid='public.notifications'::regclass
  ) THEN '✅ kaldırıldı' ELSE '❌ hâlâ bağlı — çift push riski!' END AS durum;

-- 3) Eski net.http_post trigger'ları kaldırılmış mı?
SELECT
  'B) notify_price_drops net.http_post içeriyor mu?' AS kontrol,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='notify_price_drops'
      AND p.prosrc ILIKE '%net.http_post%'
  ) THEN '❌ net.http_post hâlâ var — eski migration' ELSE '✅ temiz' END AS durum;

-- 4) CRON job kurulu mu? (en önemli kontrol)
SELECT
  'C1) pg_cron extension' AS kontrol,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_extension WHERE extname='pg_cron'
  ) THEN '✅ mevcut' ELSE '❌ pg_cron kurulu değil' END AS durum;

SELECT
  'C2) process-notification-outbox cron job' AS kontrol,
  CASE WHEN EXISTS (
    SELECT 1 FROM cron.job WHERE jobname='process-notification-outbox-every-minute'
  ) THEN '✅ kurulu' ELSE '❌ KURULMAMIŞ — push hiç gelmez! 20260802000004 migration uygulanmamış' END AS durum;

-- 5) Outbox RPC'leri mevcut mu?
SELECT
  'D) ' || p.proname AS kontrol,
  CASE WHEN has_function_privilege('service_role', p.oid::regprocedure, 'EXECUTE')
       THEN '✅ service_role erişebilir'
       ELSE '❌ service_role erişemez' END AS durum
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
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

-- 6) INTERNAL_WORKER_SECRET env var mı?
SELECT
  'E) INTERNAL_WORKER_SECRET env (worker için zorunlu)' AS kontrol,
  CASE
    WHEN current_setting('app.settings.internal_worker_secret', true) IS NOT NULL
     AND current_setting('app.settings.internal_worker_secret', true) <> ''
    THEN '✅ Postgres custom config''te ayarlı'
    ELSE '⚠️  Postgres custom config''te yok; Edge Function Deno.env ile okuyor (Dashboard > Edge Functions > Secrets)'
  END AS durum;

-- 7) Outbox durumu (son 24 saatteki istatistikler)
SELECT
  'F) Outbox istatistikleri (son 24 saat)' AS kontrol,
  to_char(NOW(), 'YYYY-MM-DD HH24:MI') AS zaman;

SELECT status, COUNT(*) AS adet, MIN(next_attempt_at) AS en_eski
FROM public.notification_outbox
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY status
ORDER BY status;

-- 8) Dead/Failed outbox varsa detay (BUG KAYNAĞI)
SELECT
  'G) Dead/Failed outbox detay' AS kontrol,
  id, status, attempts, left(last_error, 200) AS son_hata,
  next_attempt_at, created_at
FROM public.notification_outbox
WHERE status IN ('dead','failed')
  AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC
LIMIT 10;

-- 9) Pending outbox çok birikmişse worker yavaş
SELECT
  'H) Pending birikim' AS kontrol,
  COUNT(*) FILTER (WHERE status='pending') AS pending,
  COUNT(*) FILTER (WHERE status='processing') AS processing,
  COUNT(*) FILTER (WHERE status='failed') AS failed,
  MAX(EXTRACT(EPOCH FROM (NOW() - created_at)))/60 AS en_eski_dakika
FROM public.notification_outbox
WHERE created_at > NOW() - INTERVAL '1 hour';

-- 10) FCM token kayıtlı kullanıcı sayısı
SELECT
  'I) FCM token kayıtlı kullanıcı sayısı' AS kontrol,
  COUNT(*) FILTER (WHERE fcm_token IS NOT NULL AND fcm_token <> '') AS tokenli,
  COUNT(*) FILTER (WHERE fcm_token IS NULL OR fcm_token = '') AS tokensiz,
  COUNT(*) AS toplam
FROM public.profiles;

-- 11) Son 24 saatteki bildirim sayıları
SELECT
  'J) Bildirim tipleri (son 24 saat)' AS kontrol,
  type, COUNT(*) AS adet
FROM public.notifications
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY type
ORDER BY adet DESC;

-- 12) Worker'ı elle tetikle (INTERNAL_WORKER_SECRET gerekli; bulunmazsa 401 alır)
-- SELECT
--   net.http_post(
--     url     := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/process-notification-outbox',
--     headers := jsonb_build_object(
--       'x-worker-secret', '<INTERNAL_WORKER_SECRET>',
--       'Content-Type',    'application/json'
--     ),
--     body    := '{}'::jsonb
--   ) AS response_id;

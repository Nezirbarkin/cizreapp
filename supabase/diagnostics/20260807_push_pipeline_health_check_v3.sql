-- =============================================================================
-- 2026-08-07 — Push notification pipeline sağlık kontrolü (güvenli versiyon v3)
-- -----------------------------------------------------------------------------
-- AMAÇ: Neden push notification gelmediğini tespit etmek için hızlı bir
--       durum tespiti. Supabase SQL Editor'de çalıştırılır; veri yazmaz.
--
-- BU VERSİYON outbox tablosu/nesnesi yoksa bile HATA VERMEZ. Her kontrol
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

SELECT
  'A1) notification_outbox tablosu' AS kontrol,
  CASE
    WHEN to_regclass('public.notification_outbox') IS NOT NULL
    THEN '✅ mevcut'
    ELSE '❌ YOK — 20260802000003 migration canlıda uygulanmamış. Uygula: supabase db push veya SQL Editor''den 20260802000003 + 20260802000004 dosyalarını çalıştır.'
  END AS durum;

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

SELECT
  'K) app.settings.supabase_url (cron için)' AS kontrol,
  CASE
    WHEN current_setting('app.settings.supabase_url', true) IS NOT NULL
     AND current_setting('app.settings.supabase_url', true) <> ''
    THEN '✅ ayarlı: ' || current_setting('app.settings.supabase_url', true)
    ELSE '⚠️  ayarlı değil. Default (https://xsbukxkgtmdyickknqzf.supabase.co) kullanılır.'
  END AS durum;

-- ============================================================================
-- F) Outbox istatistikleri (son 24 saat) — outbox varsa DO bloğunda
-- ============================================================================

DO $f$
DECLARE
  v_exists BOOLEAN := (to_regclass('public.notification_outbox') IS NOT NULL);
  v_count  BIGINT;
  status_rec TEXT;
BEGIN
  IF NOT v_exists THEN
    RAISE NOTICE 'F) Outbox istatistikleri: ⏭️  atlandı (A1 ❌)';
    RETURN;
  END IF;

  FOREACH status_rec IN ARRAY ARRAY['pending','processing','sent','failed','dead']
  LOOP
    EXECUTE format(
      'SELECT COUNT(*) FROM public.notification_outbox
         WHERE status = %L AND created_at > NOW() - INTERVAL ''24 hours''',
      status_rec
    ) INTO v_count;
    RAISE NOTICE 'F) Outbox status=%-10s adet=%', status_rec, v_count;
  END LOOP;
END
$f$;

-- ============================================================================
-- G) Dead/Failed outbox detay
-- ============================================================================

DO $g$
DECLARE
  v_exists BOOLEAN := (to_regclass('public.notification_outbox') IS NOT NULL);
  v_rec RECORD;
BEGIN
  IF NOT v_exists THEN
    RAISE NOTICE 'G) atlandı (A1 ❌)';
    RETURN;
  END IF;

  FOR v_rec IN
    EXECUTE $sql$
      SELECT
        status,
        left(last_error, 200) AS son_hata,
        to_char(next_attempt_at, 'YYYY-MM-DD HH24:MI:SS') AS sonraki_deneme,
        attempts::text AS deneme_sayisi
      FROM public.notification_outbox
      WHERE status IN ('dead','failed')
        AND created_at > NOW() - INTERVAL '24 hours'
      ORDER BY created_at DESC
      LIMIT 10
    $sql$
  LOOP
    RAISE NOTICE 'G) status=%, hata=%, sonraki=%, deneme=%',
      v_rec.status, v_rec.son_hata, v_rec.sonraki_deneme, v_rec.deneme_sayisi;
  END LOOP;
END
$g$;

-- ============================================================================
-- H) Pending birikim (son 1 saat)
-- ============================================================================

DO $h$
DECLARE
  v_exists BOOLEAN := (to_regclass('public.notification_outbox') IS NOT NULL);
  v_rec RECORD;
BEGIN
  IF NOT v_exists THEN
    RAISE NOTICE 'H) atlandı (A1 ❌)';
    RETURN;
  END IF;

  FOR v_rec IN
    EXECUTE $sql$
      SELECT
        status,
        COUNT(*)::text AS adet,
        CASE
          WHEN MAX(created_at) IS NULL THEN '-'
          ELSE to_char(EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))/60, 'FM999990.0') || ' dk'
        END AS en_eski_dakika
      FROM public.notification_outbox
      WHERE created_at > NOW() - INTERVAL '1 hour'
      GROUP BY status
      ORDER BY status
    $sql$
  LOOP
    RAISE NOTICE 'H) status=%, adet=%, en_eski=%', v_rec.status, v_rec.adet, v_rec.en_eski_dakika;
  END LOOP;
END
$h$;

-- ============================================================================
-- I) FCM token kayıtlı kullanıcı sayısı (try/catch ile)
-- ============================================================================

DO $i$
DECLARE
  v_tokenli  BIGINT;
  v_tokensiz BIGINT;
  v_toplam   BIGINT;
BEGIN
  EXECUTE $sql$
    SELECT
      COUNT(*) FILTER (WHERE fcm_token IS NOT NULL AND fcm_token <> ''),
      COUNT(*) FILTER (WHERE fcm_token IS NULL OR fcm_token = ''),
      COUNT(*)
    FROM public.profiles
  $sql$
  INTO v_tokenli, v_tokensiz, v_toplam;
  RAISE NOTICE 'I) FCM token kayıtlı kullanıcı: tokenli=%, tokensiz=%, toplam=%',
    v_tokenli, v_tokensiz, v_toplam;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'I) FCM token istatistiği alınamadı (%). 20260803000006 sonrası SELECT grant kısıtlı. Dashboard > Table Editor > profiles üzerinden kontrol et.', SQLERRM;
END
$i$;

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
-- L) Edge Function env hatırlatıcı
-- ============================================================================

SELECT
  'L) INTERNAL_WORKER_SECRET (Edge Function env)' AS kontrol,
  '⚠️  Supabase Dashboard → Edge Functions → process-notification-outbox → Secrets. Yoksa: supabase secrets set INTERNAL_WORKER_SECRET=<SECRET> ve redeploy.' AS durum;

SELECT
  'L) FIREBASE_SERVICE_ACCOUNT (Edge Function env)' AS kontrol,
  '⚠️  Supabase Dashboard → Edge Functions → process-notification-outbox → Secrets. JSON service account dosyasının tamamı (newlines dahil). Yoksa: supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)" ve redeploy.' AS durum;

-- ============================================================================
-- 📊 SONUÇ TABLOSU — hızlı özet
-- ============================================================================

WITH kontroller AS (
  SELECT
    (to_regclass('public.notification_outbox') IS NOT NULL) AS outbox_var,
    (EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')) AS cron_var,
    (EXISTS (SELECT 1 FROM cron.job WHERE jobname='process-notification-outbox-every-minute')) AS job_var
)
SELECT
  '📊 ÖZET' AS kontrol,
  CASE
    WHEN outbox_var AND job_var THEN '✅ Tüm yapı kurulu; push çalışmalı. Bildirim gelmiyorsa: FCM token (I) veya bildirim tercihi kapalı olabilir.'
    WHEN NOT outbox_var THEN '❌ notification_outbox tablosu yok → 20260802000003 uygulanmamış. Acil: supabase/diagnostics/20260807_apply_push_pipeline_migrations.sql çalıştır.'
    WHEN outbox_var AND cron_var AND NOT job_var THEN '❌ Outbox var ama cron job yok → supabase/diagnostics/20260807_setup_cron_safe.sql çalıştır. Önce app.settings.internal_worker_secret custom config''i ayarla.'
    WHEN outbox_var AND NOT cron_var THEN '❌ pg_cron extension kurulu değil. Dashboard → Database → Extensions → pg_cron etkinleştir.'
    ELSE '⚠️  Karışık durum; yukarıdaki ❌ satırlara bak.'
  END AS durum
FROM kontroller;

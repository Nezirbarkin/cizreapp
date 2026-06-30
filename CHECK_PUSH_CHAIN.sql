-- ============================================================================
-- CHECK_PUSH_CHAIN.sql
-- ============================================================================
-- Push bildirim zincirini uçtan uca kontrol eder.
-- Aşağıdaki sırayla çalıştırın:
-- 1) Bu SQL'i çalıştırın → tüm ✅/❌ durumları görün
-- 2) Edge Function loglarını kontrol edin (Dashboard > Edge Functions > send-push-notification)
-- 3) Test siparişi oluşturun ve durumunu değiştirin
-- 4) Bu SQL'i tekrar çalıştırın → yeni satırları kontrol edin
-- ============================================================================

\echo ''
\echo '═══════════════════════════════════════════════════════════════'
\echo ' 1. pg_net EXTENSION (HTTP çağrıları için zorunlu)'
\echo '═══════════════════════════════════════════════════════════════'
SELECT
  extname,
  extversion,
  n.nspname AS schema_name,
  CASE WHEN extname = 'pg_net' THEN '✅ Yüklü' ELSE '❌ Yok' END AS durum
FROM pg_extension e
JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE extname = 'pg_net';

\echo ''
\echo '═══════════════════════════════════════════════════════════════'
\echo ' 2. SEND_PUSH_ON_NOTIFICATION FONKSİYONU'
\echo '═══════════════════════════════════════════════════════════════'
SELECT
  proname AS fonksiyon,
  CASE WHEN prosec = 1 THEN '✅ SECURITY DEFINER' ELSE '⚠️ SECURITY INVOKER' END AS guvenlik,
  proconfig::text AS search_path_ayar,
  pg_get_functiondef(oid) LIKE '%net.http_post%' AS pg_net_kullaniyor_mu,
  LENGTH(pg_get_functiondef(oid)) AS fonksiyon_boyutu
FROM pg_proc
WHERE proname = 'send_push_on_notification';

\echo ''
\echo '═══════════════════════════════════════════════════════════════'
\echo ' 3. NOTIFICATIONS_PUSH_TRIGGER DURUMU'
\echo '═══════════════════════════════════════════════════════════════'
SELECT
  trigger_name,
  event_manipulation AS olay,
  action_timing AS zamanlama,
  action_statement AS aksiyon,
  CASE WHEN trigger_name = 'notifications_push_trigger' THEN '✅ AKTİF' ELSE '❌ Pasif' END AS durum
FROM information_schema.triggers
WHERE event_object_table = 'notifications';

\echo ''
\echo '═══════════════════════════════════════════════════════════════'
\echo ' 4. FCM TOKEN İSTATİSTİKLERİ'
\echo '═══════════════════════════════════════════════════════════════'
SELECT
  COUNT(*) AS toplam_kullanici,
  COUNT(*) FILTER (WHERE fcm_token IS NOT NULL AND fcm_token != '') AS token_olan,
  COUNT(*) FILTER (WHERE fcm_token IS NULL OR fcm_token = '') AS token_olmayan,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE fcm_token IS NOT NULL AND fcm_token != '') / NULLIF(COUNT(*), 0),
    1
  ) AS yuzde_token_olan
FROM profiles;

\echo ''
\echo '═══════════════════════════════════════════════════════════════'
\echo ' 5. SON 10 SİPARİŞ BİLDİRİMİ (trigger tetiklendi mi?)'
\echo '═══════════════════════════════════════════════════════════════'
SELECT
  n.type,
  n.title,
  n.created_at,
  p.username AS alici,
  CASE WHEN p.fcm_token IS NOT NULL THEN '✅ Token var' ELSE '❌ Token yok' END AS token_durumu
FROM notifications n
LEFT JOIN profiles p ON p.id = n.user_id
WHERE n.type IN ('order_status', 'order_update', 'order_delivered', 'new_order', 'review_request', 'review_pending')
ORDER BY n.created_at DESC
LIMIT 10;

\echo ''
\echo '═══════════════════════════════════════════════════════════════'
\echo ' 6. PG_NET HTTP İSTEK LOG (varsa)'
\echo '═══════════════════════════════════════════════════════════════'
SELECT
  id,
  status_code,
  LEFT(content::text, 100) AS response_ozet,
  created
FROM net._http_response
ORDER BY created DESC
LIMIT 5;

\echo ''
\echo '═══════════════════════════════════════════════════════════════'
\echo ' 7. EDGE FUNCTION ADRESİ DOĞRU MU?'
\echo '═══════════════════════════════════════════════════════════════'
SELECT
  prosrc LIKE '%send-push-notification%' AS dogru_url_var,
  prosrc LIKE '%xsbukxkgtmdyickknqzf%' AS dogru_proje_var
FROM pg_proc
WHERE proname = 'send_push_on_notification';

\echo ''
\echo '═══════════════════════════════════════════════════════════════'
\echo ' KONTROL TAMAMLANDI'
\echo '═══════════════════════════════════════════════════════════════'
\echo ''
\echo 'SORUN VARSA:'
\echo '  → FIX_ORDER_STATUS_PUSH_NOTIFICATION.sql çalıştırın'
\echo ''
\echo 'EDGE FUNCTION LOG KONTROL:'
\echo '  → Dashboard > Edge Functions > send-push-notification > Logs'
\echo ''
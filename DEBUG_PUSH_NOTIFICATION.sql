-- ============================================================================
-- KONTROL: Push Notification Sistemi Debug
-- ============================================================================
-- Edge Function çağrılıyor ama push gönderilmiyor (sent_count: 0, error_count: 1)

-- 1. FCM token'ları kontrol et
SELECT 
    id,
    username,
    CASE 
        WHEN fcm_token IS NULL THEN '❌ NULL'
        WHEN fcm_token = '' THEN '❌ Empty'
        WHEN LENGTH(fcm_token) < 100 THEN '⚠️ Too short (' || LENGTH(fcm_token) || ' chars)'
        ELSE '✅ OK (' || LENGTH(fcm_token) || ' chars)'
    END as token_status,
    LEFT(fcm_token, 50) || '...' as token_preview,
    updated_at
FROM profiles
WHERE fcm_token IS NOT NULL AND fcm_token != ''
ORDER BY updated_at DESC
LIMIT 10;

-- 2. Son gönderilen bildirimleri kontrol et
SELECT 
    n.id,
    n.user_id,
    n.type,
    n.title,
    n.content,
    p.username,
    CASE 
        WHEN p.fcm_token IS NULL THEN '❌ No FCM token'
        WHEN p.fcm_token = '' THEN '❌ Empty FCM token'
        ELSE '✅ Has FCM token'
    END as user_fcm_status,
    n.created_at
FROM notifications n
JOIN profiles p ON p.id = n.user_id
WHERE n.created_at > NOW() - INTERVAL '1 hour'
ORDER BY n.created_at DESC
LIMIT 10;

-- 3. Edge Function yanıtlarını kontrol et
SELECT 
    id,
    status_code,
    content,
    error_msg,
    created
FROM net._http_response
ORDER BY created DESC
LIMIT 5;

-- 4. Firebase Service Account kontrolü için yardım mesajı
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
    RAISE NOTICE 'PUSH NOTIFICATION DEBUG BİLGİLERİ';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
    RAISE NOTICE '';
    RAISE NOTICE 'Eğer FCM token''lar varsa ancak push gitm
iyorsa:';
    RAISE NOTICE '';
    RAISE NOTICE '1. Firebase Service Account kontrolü:';
    RAISE NOTICE '   Dashboard > Edge Functions > Secrets';
    RAISE NOTICE '   FIREBASE_SERVICE_ACCOUNT secret''ının olduğundan emin olun';
    RAISE NOTICE '';
    RAISE NOTICE '2. Edge Function loglarını kontrol edin:';
    RAISE NOTICE '   Dashboard > Edge Functions > send-push-notification > Logs';
    RAISE NOTICE '   Hata mesajı "No FCM tokens found" ise token problemi';
    RAISE NOTICE '   Hata mesajı "FCM error" ise Firebase yapılandırma problemi';
    RAISE NOTICE '';
    RAISE NOTICE '3. FCM token''ları yeniden kaydetmek için:';
    RAISE NOTICE '   Uygulamayı kapatıp açın ve giriş yapın';
    RAISE NOTICE '   Firebase Console > Cloud Messaging bölümünü kontrol edin';
    RAISE NOTICE '';
    RAISE NOTICE '4. Test için manuel push göndermek:';
    RAISE NOTICE '   SELECT net.http_post(';
    RAISE NOTICE '     url := ''https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification'',';
    RAISE NOTICE '     headers := jsonb_build_object(''Authorization'', ''Bearer YOUR_ANON_KEY'', ''Content-Type'', ''application/json''),';
    RAISE NOTICE '     body := jsonb_build_object(''user_id'', ''USER_ID'', ''title'', ''Test'', ''body'', ''Test message'')';
    RAISE NOTICE '   );';
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
END $$;

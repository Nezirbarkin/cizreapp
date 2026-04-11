-- =====================================================
-- FIREBASE PUSH - EDGE FUNCTION İLE GÜNCELLEME
-- =====================================================
--
-- Supabase Edge Function'dan Firebase FCM HTTP v1 API kullanarak
-- push notification gönderir
--
-- =====================================================

-- 1. Edge Function'a istek atan fonksiyon
CREATE OR REPLACE FUNCTION send_fcm_push_notification(
    p_user_id uuid,
    p_title text,
    p_body text,
    p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_edge_function_url text := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push';
    v_service_role_key text;
    v_result jsonb;
    v_http_response record;
BEGIN
    -- Service role key'i environment variable'dan al
    -- NOT: Bu değişken Supabase tarafından otomatik set edilir
    -- Eğer erişim yoksa manuel eklemeniz gerekebilir
    
    RAISE NOTICE 'Calling Edge Function for user %', p_user_id;
    RAISE NOTICE 'Edge Function URL: %', v_edge_function_url;
    
    -- Edge Function'a POST isteği at
    -- NOT: Authorization header'ı eklemeye gerek yok
    -- Çünkü internal istek (database -> edge function)
    SELECT * INTO v_http_response FROM net.http_post(
        url := v_edge_function_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
        ),
        body := jsonb_build_object(
            'user_id', p_user_id,
            'title', p_title,
            'body', p_body,
            'data', p_data
        ),
        timeout_milliseconds := 10000
    );
    
    -- Response'u parse et
    BEGIN
        v_result := v_http_response.content::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_result := jsonb_build_object(
            'success', false,
            'error', 'Failed to parse Edge Function response',
            'raw_response', v_http_response.content
        );
    END;
    
    RAISE NOTICE 'Edge Function response: %', v_result;
    
    RETURN v_result;
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'send_fcm_push_notification error: %', SQLERRM;
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM,
        'detail', 'Failed to call Edge Function'
    );
END;
$$;

-- 2. send_push_on_notification fonksiyonu (değişiklik yok)
-- Zaten mevcut, sadece send_fcm_push_notification'ı çağırıyor

-- 3. TEST: Edge Function çağrısı
-- NOT: Kendi user ID'nizi kullanın
/*
SELECT send_fcm_push_notification(
    'SIZIN_USER_ID',
    'Test Push',
    'Bu bir test bildirimidir',
    '{"type": "test"}'::jsonb
);
*/

-- 4. KONTROL: Fonksiyon güncellendi mi?
SELECT 
    routine_name,
    routine_type,
    data_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'send_fcm_push_notification';

-- =====================================================
-- EDGE FUNCTION DEPLOY ADIMLARI:
-- =====================================================
-- 
-- 1. Firebase Service Account JSON'unu hazırlayın
--    (Firebase Console → Project Settings → Service Accounts → Generate New Private Key)
--
-- 2. Supabase CLI'yi kurun (eğer yoksa):
--    npm install -g supabase
--
-- 3. Projenizle bağlantı kurun:
--    supabase login
--    supabase link --project-ref xsbukxkgtmdyickknqzf
--
-- 4. Edge Function secret'ı ekleyin:
--    supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account", ...}'
--
-- 5. Edge Function'ı deploy edin:
--    supabase functions deploy send-push
--
-- 6. Test edin:
--    SELECT send_fcm_push_notification('YOUR_USER_ID', 'Test', 'Message');
--
-- =====================================================
-- ALTERNATİF: Dashboard'dan Deploy
-- =====================================================
--
-- 1. Supabase Dashboard → Edge Functions → Create Function
-- 2. Function name: send-push
-- 3. supabase/functions/send-push/index.ts dosyasını yapıştırın
-- 4. Secrets → Add Secret:
--    Name: FIREBASE_SERVICE_ACCOUNT
--    Value: {Firebase service account JSON}
-- 5. Deploy butonuna tıklayın
--
-- =====================================================

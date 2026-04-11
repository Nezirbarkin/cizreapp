-- =====================================================
-- FIRE-AND-FORGET PUSH NOTIFICATION
-- =====================================================
--
-- pg_net asenkron çalışır, response beklemeye gerek yok
-- Sadece HTTP isteğini başlat ve trigger'ı sonlandır
--
-- =====================================================

-- send_fcm_push_notification - Fire-and-Forget
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
    v_edge_function_url text := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
    v_request_id bigint;
BEGIN
    RAISE NOTICE 'Sending async push notification for user %', p_user_id;
    
    -- Edge Function'a asenkron POST isteği at
    -- net.http_post sadece request_id döndürür, response beklemez
    SELECT net.http_post(
        url := v_edge_function_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
        ),
        body := jsonb_build_object(
            'user_id', p_user_id::text,
            'title', p_title,
            'body', p_body,
            'data', p_data
        ),
        timeout_milliseconds := 10000
    ) INTO v_request_id;
    
    RAISE NOTICE 'HTTP request queued with ID: %', v_request_id;
    
    -- Başarılı bir şekilde kuyruğa eklendi
    RETURN jsonb_build_object(
        'success', true,
        'request_id', v_request_id,
        'message', 'Push notification request queued'
    );
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'send_fcm_push_notification error: %', SQLERRM;
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM,
        'detail', 'Failed to queue push notification'
    );
END;
$$;

-- =====================================================
-- KONTROL
-- =====================================================
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'send_fcm_push_notification';

-- =====================================================
-- SONUÇ
-- =====================================================
-- ✅ pg_net asenkron HTTP desteği ile fire-and-forget
-- ✅ Response beklenmez, hemen return eder
-- ✅ Edge Function arka planda çalışır
-- ✅ Trigger performansı etkilenmez
-- =====================================================

-- =====================================================
-- EDGE FUNCTION URL DÜZELTMESİ
-- =====================================================
--
-- SQL fonksiyonu yanlış URL çağırıyor:
-- Mevcut Edge Function: send-push-notification
-- SQL çağırıyor: send-push
--
-- =====================================================

-- send_fcm_push_notification fonksiyonunu doğru URL ile güncelle
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
    v_result jsonb;
    v_http_response record;
BEGIN
    RAISE NOTICE 'Calling Edge Function for user %', p_user_id;
    RAISE NOTICE 'Edge Function URL: %', v_edge_function_url;
    
    -- Edge Function'a POST isteği at
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
            'raw_response', v_http_response.content,
            'http_status', v_http_response.status
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
-- ✅ Edge Function URL düzeltildi:
--    /send-push → /send-push-notification
-- =====================================================

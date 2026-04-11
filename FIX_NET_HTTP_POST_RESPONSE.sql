-- =====================================================
-- NET.HTTP_POST RESPONSE YAPISI DÜZELTME
-- =====================================================
--
-- net.http_post 'content' değil 'body' döndürür
--
-- =====================================================

-- send_fcm_push_notification fonksiyonunu düzelt
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
    v_response_body text;
    v_http_status int;
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
            'user_id', p_user_id::text,
            'title', p_title,
            'body', p_body,
            'data', p_data
        ),
        timeout_milliseconds := 10000
    );
    
    -- Response'dan body ve status al
    -- net.http_post returns: status (int), headers (jsonb), body (text)
    v_http_status := v_http_response.status;
    v_response_body := v_http_response.body;
    
    RAISE NOTICE 'HTTP Status: %', v_http_status;
    RAISE NOTICE 'Response Body: %', v_response_body;
    
    -- Response'u parse et
    BEGIN
        v_result := v_response_body::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_result := jsonb_build_object(
            'success', false,
            'error', 'Failed to parse Edge Function response',
            'raw_response', v_response_body,
            'http_status', v_http_status
        );
    END;
    
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
-- TEST: Kendi user ID'nizle test edin
-- =====================================================
/*
SELECT send_fcm_push_notification(
    'SIZIN_USER_ID',
    'Test Push',
    'Bu bir test bildirimidir'
);
*/

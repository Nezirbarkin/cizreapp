-- =====================================================
-- EDGE FUNCTION INTERNAL CALL - AUTH HEADER KALDIRMA
-- =====================================================
--
-- Internal Edge Function çağrılarında
-- Authorization header gerekmez
--
-- =====================================================

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
    -- Authorization header YOK (internal call)
    SELECT net.http_post(
        url := v_edge_function_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json'
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
-- TEST
-- =====================================================
SELECT send_fcm_push_notification(
    'SIZIN_USER_ID',
    'Test Push',
    'Bu bir test bildirimidir'
);

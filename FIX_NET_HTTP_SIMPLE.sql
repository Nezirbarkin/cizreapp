-- =====================================================
-- NET.HTTP_POST BASİT ÇÖZÜM
-- =====================================================
--
-- Tüm response'u JSON olarak alıp parse et
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
    v_response record;
BEGIN
    RAISE NOTICE 'Calling Edge Function for user %', p_user_id;
    RAISE NOTICE 'Edge Function URL: %', v_edge_function_url;
    
    -- Edge Function'a POST isteği at
    -- net.http_post returns a record with various fields
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
    ) INTO v_response;
    
    -- Response'u JSON olarak döndür (tüm field'larla)
    RAISE NOTICE 'Response record type: %', pg_typeof(v_response);
    
    -- pg_net http_post response field'larını kontrol et
    -- Genellikle: status (int), body (text), headers (jsonb)
    -- Ama field isimleri farklı olabilir, bu yüzden row_to_json kullan
    
    -- Önce body'yi almayı dene
    BEGIN
        -- Field isimlerini dene: body, content, response
        IF v_response IS NOT NULL THEN
            -- row_to_json ile tüm response'u JSON'a çevir
            v_result := row_to_json(v_response)::jsonb;
            RAISE NOTICE 'Raw response: %', v_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Error parsing response: %', SQLERRM;
        v_result := jsonb_build_object(
            'success', false,
            'error', SQLERRM,
            'raw_response', 'Could not parse'
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
-- TEST
-- =====================================================
SELECT send_fcm_push_notification(
    'SIZIN_USER_ID',
    'Test Push',
    'Bu bir test bildirimidir'
);

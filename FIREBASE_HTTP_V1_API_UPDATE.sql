-- =====================================================
-- FIREBASE FCM HTTP V1 API - GÜNCELLENMİŞ VERSİYON
-- =====================================================
--
-- Firebase Cloud Messaging API (V1) kullanıyoruz
-- Legacy API deprecated olduğu için HTTP v1 API'ye geçtik
--
-- =====================================================

-- 1. Firebase service account'tan project_id al
CREATE OR REPLACE FUNCTION get_firebase_project_id()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_service_account jsonb;
    v_project_id text;
BEGIN
    -- Service account JSON'unu vault'tan al
    SELECT secret::jsonb INTO v_service_account
    FROM vault.secrets
    WHERE name = 'firebase_service_account'
    LIMIT 1;
    
    IF v_service_account IS NULL THEN
        RAISE EXCEPTION 'Firebase service account not found in vault';
    END IF;
    
    -- Project ID'yi döndür
    v_project_id := v_service_account->>'project_id';
    
    IF v_project_id IS NULL THEN
        RAISE EXCEPTION 'project_id not found in service account';
    END IF;
    
    RETURN v_project_id;
END;
$$;

-- 2. FCM HTTP v1 API ile push gönder
CREATE OR REPLACE FUNCTION send_fcm_push_notification_v1(
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
    v_project_id text;
    v_fcm_url text;
    v_access_token text;
    v_token_record record;
    v_result jsonb;
    v_success_count int := 0;
    v_error_count int := 0;
    v_tokens text[] := '{}';
    v_service_account jsonb;
BEGIN
    -- Project ID'yi al
    v_project_id := get_firebase_project_id();
    
    -- Service account JSON'unu al
    SELECT secret::jsonb INTO v_service_account
    FROM vault.secrets
    WHERE name = 'firebase_service_account'
    LIMIT 1;
    
    IF v_service_account IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Firebase service account not found in vault'
        );
    END IF;
    
    -- FCM URL (HTTP v1 API)
    v_fcm_url := 'https://fcm.googleapis.com/v1/projects/' || v_project_id || '/messages:send';
    
    RAISE NOTICE 'FCM URL: %', v_fcm_url;
    
    -- Tokenları topla
    FOR v_token_record IN
        SELECT fcm_token as token FROM profiles WHERE id = p_user_id AND fcm_token IS NOT NULL
        UNION
        SELECT token FROM notification_tokens WHERE user_id = p_user_id
    LOOP
        v_tokens := array_append(v_tokens, v_token_record.token);
    END LOOP;
    
    IF array_length(v_tokens, 1) IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'No FCM tokens found',
            'user_id', p_user_id
        );
    END IF;
    
    RAISE NOTICE 'Found % tokens', array_length(v_tokens, 1);
    
    -- HTTP v1 API için OAuth2 access token gerekli
    -- PostgreSQL'de JWT imzalama zor olduğu için
    -- Supabase Edge Function kullanmanızı öneriyoruz
    
    -- Placeholder: Bu fonksiyon HTTP v1 API'yi kullanamıyor
    -- Çünkü OAuth2 token gerekli ve PostgreSQL'de JWT imzalama zor
    
    RAISE WARNING 'HTTP v1 API requires OAuth2 token. Use Edge Function instead.';
    
    RETURN jsonb_build_object(
        'success', false,
        'error', 'HTTP v1 API requires OAuth2 token (JWT signing)',
        'solution', 'Use Supabase Edge Function for FCM HTTP v1 API',
        'alt_solution', 'Enable Firebase Legacy API or use Flutter-side FCM'
    );
    
END;
$$;

-- =====================================================
-- ALTERNATİF: Edge Function çağrısı
-- =====================================================
-- Supabase Edge Function kullanarak HTTP v1 API'ye istek atabiliriz
-- Bu daha güvenilir ve performanslıdır

-- 3. Edge Function ile push gönder
CREATE OR REPLACE FUNCTION send_fcm_push_notification_via_edge(
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
    v_edge_function_url text := 'https://YOUR_PROJECT.supabase.co/functions/v1/send-push';
    v_response jsonb;
BEGIN
    -- Tokenları kontrol et
    IF NOT EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = p_user_id AND fcm_token IS NOT NULL
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'No FCM token found'
        );
    END IF;
    
    -- Edge Function'a istek at
    -- NOT: Bu Edge Function'ı ayrı oluşturmanız gerekiyor
    SELECT net.http_post(
        url := v_edge_function_url,
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || current_setting('app.service_role_key')::text,
            'Content-Type', 'application/json'
        ),
        body := jsonb_build_object(
            'user_id', p_user_id,
            'title', p_title,
            'body', p_body,
            'data', p_data
        )
    ) INTO v_response;
    
    RETURN v_response;
END;
$$;

-- =====================================================
-- KONTROL
-- =====================================================
SELECT get_firebase_project_id() as project_id;

-- =====================================================
-- SONUÇ
-- =====================================================
-- Firebase Legacy API disabled olduğu için:
-- 1. HTTP v1 API kullanmalıyız (OAuth2 token gerekli)
-- 2. PostgreSQL'de JWT imzalama zor olduğu için
-- 3. Supabase Edge Function kullanmanızı öneriyoruz
-- 4. VEYA Flutter tarafında Firebase Admin SDK kullanın
-- =====================================================

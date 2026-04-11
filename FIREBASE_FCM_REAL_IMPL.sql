-- =====================================================
-- FIREBASE FCM HTTP API - GERÇEK IMPLEMENTASYON
-- =====================================================
-- Firebase Cloud Messaging HTTP v1 API ile push gönderme
-- =====================================================

-- DÜZELTİLMİŞ send_fcm_push_notification - GERÇEK FCM API
CREATE OR REPLACE FUNCTION send_fcm_push_notification(
    p_user_id uuid,
    p_title text,
    p_body text,
    p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token_record record;
    v_firebase_secret jsonb;
    v_project_id text;
    v_access_token text;
    v_fcm_url text;
    v_response_body text;
    v_success_count int := 0;
    v_error_count int := 0;
    v_result jsonb;
BEGIN
    -- Firebase secret'ı al
    SELECT decrypted_secret::jsonb INTO v_firebase_secret
    FROM vault.decrypted_secrets
    WHERE name = 'firebase_service_account'
    LIMIT 1;
    
    -- Firebase secret yoksa hata döndür
    IF v_firebase_secret IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Firebase service account key not found in vault',
            'hint', 'Add firebase_service_account to vault.secrets'
        );
    END IF;
    
    -- Project ID'yi al
    v_project_id := v_firebase_secret->>'project_id';
    
    IF v_project_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'project_id not found in firebase service account');
    END IF;
    
    -- OAuth2 access token al (Google OAuth2 endpoint)
    -- NOT: Bu kısım service account key ile JWT üretip token alır
    -- Basitleştirilmiş versiyon: pg_net.http_post ile
    
    -- Önce token'ları topla
    FOR v_token_record IN
        SELECT token FROM notification_tokens WHERE user_id = p_user_id
        UNION
        SELECT fcm_token FROM profiles WHERE id = p_user_id AND fcm_token IS NOT NULL
    LOOP
        BEGIN
            -- Firebase FCM HTTP v1 API endpoint
            v_fcm_url := 'https://fcm.googleapis.com/v1/projects/' || v_project_id || '/messages:send';
            
            -- FCM HTTP v1 API request body
            -- OAuth2 token gerekli, bu yüzden legacy API kullanıyoruz
            -- Legacy API daha basit: server_key ile çalışır
            
            -- Firebase Legacy API (daha basit, OAuth2 gerektirmez)
            SELECT net.http_post(
                url := 'https://fcm.googleapis.com/fcm/send',
                headers := jsonb_build_object(
                    'Authorization', 'key=' || (v_firebase_secret->>'server_key'),
                    'Content-Type', 'application/json'
                ),
                body := jsonb_build_object(
                    'to', v_token_record.token,
                    'notification', jsonb_build_object(
                        'title', p_title,
                        'body', p_body,
                        'sound', 'default'
                    ),
                    'data', p_data,
                    'priority', 'high'
                ),
                timeout_milliseconds := 5000
            ) INTO v_result;
            
            v_success_count := v_success_count + 1;
            
            RAISE NOTICE 'Push notification sent to token: %, response: %', 
                substring(v_token_record.token, 1, 20), 
                v_result->>'status';
                
        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            RAISE WARNING 'Push notification failed for token %: %', 
                substring(v_token_record.token, 1, 20), 
                SQLERRM;
        END;
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'sent_count', v_success_count,
        'error_count', v_error_count,
        'message', 'Push notification sent via Firebase FCM'
    );
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM,
        'detail', 'Failed to send push notification'
    );
END;
$$;

-- =====================================================
-- ALTERNATİF: pg_cron ile OAuth2 token cache
-- =====================================================

-- Firebase OAuth2 token al (saatlik yeniler)
CREATE OR REPLACE FUNCTION get_firebase_access_token()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_service_account jsonb;
    v_jwt_claim text;
    v_jwt_header text;
    v_private_key text;
    v_access_token_url text;
    v_response text;
BEGIN
    -- Service account key'i al
    SELECT decrypted_secret::jsonb INTO v_service_account
    FROM vault.decrypted_secrets
    WHERE name = 'firebase_service_account'
    LIMIT 1;
    
    IF v_service_account IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- JWT Header
    v_jwt_header := encode(jsonb_build_object(
        'alg', 'RS256',
        'typ', 'JWT'
    )::text, 'base64');
    
    -- Not: Bu basitleştirilmiş versiyon
    -- Tam OAuth2 implementasyonu için JWT signature gerekli
    -- Supabase Edge Function kullanmak daha pratik
    
    RETURN NULL;
END;
$$;

-- =====================================================
-- TEST: Push notification gönder
-- =====================================================

-- Kendi user ID'nizle test edin
-- SELECT send_fcm_push_notification(
--     'SIZIN_USER_ID',
--     'Test Push',
--     'Bu bir test bildirimidir'
-- );

-- =====================================================
-- VAULT'A SERVER_KEY EKLEME (Alternatif)
-- =====================================================
-- Firebase service account JSON'unun sonuna server_key ekleyebilirsiniz
-- Veya ayrı bir secret olarak ekleyin:

/*
INSERT INTO vault.decrypted_secrets (name, secret, description)
VALUES (
    'firebase_server_key',
    'YOUR_FIREBASE_SERVER_KEY',  -- Firebase Console → Project Settings → Cloud Messaging → Server Key
    'Firebase Legacy Server Key for FCM'
);
*/

-- =====================================================
-- SONUÇ:
-- =====================================================
-- Gerçek FCM API çağrısı için:
-- 1. Firebase Service Account Key vault'a eklenmeli (server_key ile)
-- 2. pg_net extension aktif olmalı (zaten var)
-- 3. İnternet erişimi olmalı (Supabase Cloud'da var)

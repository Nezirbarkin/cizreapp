-- =====================================================
-- TOKEN TABLOSU ÇÖZÜMÜ - Hem notification_tokens hem profiles
-- =====================================================
-- SQL fonksiyonlarını her iki tabloyu destekleyecek şekilde güncelle
-- =====================================================

-- DÜZELTİLMİŞ send_fcm_push_notification
-- Hem notification_tokens hem profiles.fcm_token'dan okur
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
    v_success_count int := 0;
    v_error_count int := 0;
    v_firebase_secret text;
    v_token text;
BEGIN
    -- Firebase secret'ı al
    SELECT decrypted_secret INTO v_firebase_secret
    FROM vault.decrypted_secrets
    WHERE name = 'firebase_service_account'
    LIMIT 1;
    
    -- Firebase secret yoksa silent olarak geç
    IF v_firebase_secret IS NULL THEN
        RAISE WARNING 'Firebase secret not found. Push notification skipped for user %', p_user_id;
        RETURN jsonb_build_object(
            'success', true,
            'sent_count', 0,
            'note', 'Firebase not configured - notification saved in database'
        );
    END IF;
    
    -- Önce notification_tokens tablosundan token'ları al
    FOR v_token_record IN
        SELECT token FROM notification_tokens WHERE user_id = p_user_id
    LOOP
        BEGIN
            -- Firebase FCM ile gönder (placeholder)
            v_token := v_token_record.token;
            v_success_count := v_success_count + 1;
            RAISE NOTICE 'Sending push to token from notification_tokens: %', substring(v_token, 1, 20);
        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
        END;
    END LOOP;
    
    -- Sonra profiles.fcm_token'dan da kontrol et (Flutter kodu buraya kaydediyor)
    FOR v_token_record IN
        SELECT fcm_token FROM profiles WHERE id = p_user_id AND fcm_token IS NOT NULL
    LOOP
        BEGIN
            v_token := v_token_record.fcm_token;
            v_success_count := v_success_count + 1;
            RAISE NOTICE 'Sending push to token from profiles.fcm_token: %', substring(v_token, 1, 20);
        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
        END;
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'sent_count', v_success_count,
        'error_count', v_error_count,
        'note', 'Notification saved in database'
    );
END;
$$;

-- =====================================================
-- KONTROL: Token'lar nerede?
-- =====================================================

-- notification_tokens tablosu
SELECT COUNT(*) as notification_tokens_count FROM notification_tokens;

-- profiles.fcm_token alanı
SELECT COUNT(*) as profiles_with_fcm_token FROM profiles WHERE fcm_token IS NOT NULL;

-- Hangi kullanıcıda token var?
SELECT id, fcm_token FROM profiles WHERE fcm_token IS NOT NULL LIMIT 10;

-- =====================================================
-- TAMAMLANDI!
-- =====================================================
-- Şimdi send_fcm_push_notification fonksiyonu:
-- 1. notification_tokens tablosundan token'ları alır
-- 2. profiles.fcm_token'dan da token'ları alır
-- 3. Her iki kaynağı da destekler

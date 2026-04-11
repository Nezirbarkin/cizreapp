-- =====================================================
-- FIREBASE PUSH NOTIFICATION - SERVER KEY İLE GÜNCELLEME
-- =====================================================

-- 1. Mevcut send_fcm_push_notification fonksiyonunu güncelle
-- Vault'dan firebase_server_key okuyacak şekilde
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
    v_token_record record;
    v_server_key text;
    v_fcm_url text := 'https://fcm.googleapis.com/fcm/send';
    v_result jsonb;
    v_success_count int := 0;
    v_error_count int := 0;
    v_tokens text[] := '{}';
BEGIN
    -- Firebase Server Key'i vault'dan al
    -- Not: decrypted_secrets yerine secrets tablosunu kullanıyoruz
    SELECT secret INTO v_server_key
    FROM vault.secrets
    WHERE name = 'firebase_server_key'
    LIMIT 1;
    
    -- Server key yoksa hata döndür ama log olarak kaydet
    IF v_server_key IS NULL THEN
        RAISE WARNING 'Firebase server key not found in vault!';
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Firebase server key not found in vault',
            'hint', 'Add firebase_server_key to vault.secrets (see FIREBASE_SERVER_KEY_GUIDE.md)'
        );
    END IF;
    
    -- RAISE NOTICE ile debug bilgi
    RAISE NOTICE 'Firebase server key found: % chars', LENGTH(v_server_key);
    
    -- Tokenları topla (hem notification_tokens hem profiles.fcm_token)
    -- NOT: profiles.fcm_token daha güvenilir çünkü Flutter oraya kaydediyor
    FOR v_token_record IN
        SELECT fcm_token as token FROM profiles WHERE id = p_user_id AND fcm_token IS NOT NULL
        UNION
        SELECT token FROM notification_tokens WHERE user_id = p_user_id
    LOOP
        v_tokens := array_append(v_tokens, v_token_record.token);
    END LOOP;
    
    -- Token yoksa hata döndür
    IF array_length(v_tokens, 1) IS NULL THEN
        RAISE WARNING 'No FCM tokens found for user %', p_user_id;
        RETURN jsonb_build_object(
            'success', false,
            'error', 'No FCM tokens found',
            'user_id', p_user_id
        );
    END IF;
    
    RAISE NOTICE 'Found % FCM tokens for user %', array_length(v_tokens, 1), p_user_id;
    
    -- Her token için Firebase'e istek gönder
    FOREACH v_token_record.token IN ARRAY v_tokens
    LOOP
        BEGIN
            -- Firebase Legacy API çağrısı
            SELECT net.http_post(
                url := v_fcm_url,
                headers := jsonb_build_object(
                    'Authorization', 'key=' || v_server_key,
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
            
            RAISE NOTICE 'Push sent to token: %, status: %', 
                substring(v_token_record.token, 1, 20), 
                v_result->>'status';
                
        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            RAISE WARNING 'Push failed for token %: %', 
                substring(v_token_record.token, 1, 20), 
                SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE 'Push notification completed: % sent, % errors', 
        v_success_count, v_error_count;
    
    RETURN jsonb_build_object(
        'success', true,
        'sent_count', v_success_count,
        'error_count', v_error_count,
        'message', 'Push notification sent via Firebase FCM'
    );
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'send_fcm_push_notification error: %', SQLERRM;
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM,
        'detail', 'Failed to send push notification'
    );
END;
$$;

-- 2. send_push_on_notification fonksiyonunu güncelle
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_prefs record;
    v_should_send boolean := false;
    v_result jsonb;
BEGIN
    -- Bildirim tercihlerini al
    SELECT * INTO v_prefs
    FROM notification_preferences
    WHERE user_id = NEW.user_id;
    
    -- Tercih yoksa varsayılan olarak gönder (true)
    IF v_prefs IS NULL THEN
        v_should_send := true;
    ELSE
        -- Tip bazlı kontrol
        CASE NEW.type
            WHEN 'like' THEN v_should_send := COALESCE(v_prefs.push_likes, true);
            WHEN 'comment' THEN v_should_send := COALESCE(v_prefs.push_comments, true);
            WHEN 'follow' THEN v_should_send := COALESCE(v_prefs.push_follows, true);
            WHEN 'follow_request' THEN v_should_send := COALESCE(v_prefs.push_follows, true);
            WHEN 'follow_request_accepted' THEN v_should_send := COALESCE(v_prefs.push_follows, true);
            WHEN 'mention' THEN v_should_send := COALESCE(v_prefs.push_mentions, true);
            WHEN 'message' THEN v_should_send := COALESCE(v_prefs.push_messages, true);
            ELSE v_should_send := true; -- Varsayılan: gönder
        END CASE;
        
        -- Global kontrol
        IF v_prefs.push_enabled = false THEN
            v_should_send := false;
        END IF;
    END IF;
    
    -- Push gönderilmeliyse
    IF v_should_send THEN
        RAISE NOTICE 'Sending push for notification % (type: %)', NEW.id, NEW.type;
        
        -- Firebase'e push gönder
        SELECT send_fcm_push_notification(
            NEW.user_id,
            NEW.title,
            NEW.content,
            jsonb_build_object(
                'type', NEW.type,
                'notification_id', NEW.id::text,
                'actor_id', COALESCE(NEW.actor_id::text, ''),
                'entity_id', COALESCE(NEW.entity_id, '')
            )
        ) INTO v_result;
        
        RAISE NOTICE 'Push result: %', v_result::text;
    ELSE
        RAISE NOTICE 'Push disabled for notification % (type: %)', NEW.id, NEW.type;
    END IF;
    
    RETURN NEW;
END;
$$;

-- 3. Kontrol: Fonksiyonlar oluşturuldu mu?
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN ('send_fcm_push_notification', 'send_push_on_notification');

-- 4. Kontrol: Trigger mevcut mu?
SELECT 
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'notifications'
AND trigger_schema = 'public'
AND trigger_name = 'push_notification_trigger';

-- =====================================================
-- TEST: Kendi user ID'nizle push gönderin
-- =====================================================
-- SELECT send_fcm_push_notification(
--     'SIZIN_USER_ID',
--     'Test Push',
--     'Bu bir test bildirimidir'
-- );

-- =====================================================
-- SONUÇ
-- =====================================================
-- ✅ send_fcm_push_notification güncellendi (vault.secrets'ten okuyor)
-- ✅ send_push_on_notification güncellendi
-- ✅ Push notification tetiklenecek
-- ⚠️ firebase_server_key vault'a eklenmeli!
-- =====================================================

-- =====================================================
-- NOTIFICATION PREFERENCES FIELD İSIMLERİ DÜZELTME
-- =====================================================
--
-- send_push_on_notification fonksiyonunu
-- gerçek field isimleri ile güncelleme
--
-- =====================================================

-- send_push_on_notification fonksiyonunu düzelt
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
        -- Global kontrol önce
        IF v_prefs.push_enabled = false THEN
            v_should_send := false;
        ELSE
            -- Tip bazlı kontrol (GERÇEK FIELD İSİMLERİ)
            CASE NEW.type
                WHEN 'like' THEN v_should_send := COALESCE(v_prefs.likes_enabled, true);
                WHEN 'comment' THEN v_should_send := COALESCE(v_prefs.comments_enabled, true);
                WHEN 'follow' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
                WHEN 'follow_request' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
                WHEN 'follow_request_accepted' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
                WHEN 'mention' THEN v_should_send := COALESCE(v_prefs.mentions, true);
                WHEN 'message' THEN v_should_send := true; -- Mesajlar için field yok, varsayılan true
                WHEN 'order' THEN v_should_send := COALESCE(v_prefs.order_updates_enabled, true);
                WHEN 'courier_request' THEN v_should_send := true;
                WHEN 'courier_request_approved' THEN v_should_send := true;
                WHEN 'courier_request_rejected' THEN v_should_send := true;
                WHEN 'shop' THEN v_should_send := true;
                WHEN 'promotion' THEN v_should_send := COALESCE(v_prefs.promotional_enabled, true);
                WHEN 'system' THEN v_should_send := true;
                ELSE v_should_send := true; -- Varsayılan: gönder
            END CASE;
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

-- =====================================================
-- KONTROL
-- =====================================================
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'send_push_on_notification';

-- =====================================================
-- SONUÇ
-- =====================================================
-- ✅ send_push_on_notification güncellendi
-- ✅ Gerçek field isimleri kullanılıyor:
--    - likes_enabled (push_likes değil)
--    - comments_enabled (push_comments değil)
--    - followers_enabled (push_follows değil)
-- =====================================================

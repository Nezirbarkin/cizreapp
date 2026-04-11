-- ============================================================================
-- CHAT SİSTEMİ TAM DÜZELTME
-- ============================================================================
-- 1. Yeni mesajda karşı taraf için conversation oluştur (sohbet görünmesi için)
-- 2. Yeni mesajda push notification gönder (FCM bildirimi için)

-- ============================================================================
-- BÖLÜM 1: CONVERSATION CREATE TRIGGER (Sohbet görünmesi için)
-- ============================================================================

DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP FUNCTION IF EXISTS update_conversation_on_message();

CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    -- Gönderen ve alıcı kullanıcı ID'leri
    v_sender_id UUID := NEW.sender_id;
    v_conv_id UUID := NEW.conversation_id;
    
    -- Mevcut conversation bilgileri
    v_user_id UUID;
    v_other_user_id UUID;
    
    -- Karşı tarafın conversation ID'si
    v_other_conv_id UUID;
    
    -- Push notification için değişkenler
    v_recipient_id UUID;
    v_sender_name TEXT;
    v_recipient_fcm_token TEXT;
    v_notification_payload JSONB;
BEGIN
    -- Mevcut conversation bilgilerini al
    SELECT user_id, other_user_id INTO v_user_id, v_other_user_id
    FROM conversations
    WHERE id = v_conv_id;
    
    -- MEVCUT CONVERSATION'I GÜNCELLE
    UPDATE conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW(),
        unread_count = CASE
            -- Karşı taraftan mesaj geldiyse unread_count artır
            WHEN user_id != v_sender_id THEN unread_count + 1
            ELSE unread_count
        END
    WHERE id = v_conv_id;
    
    -- KARŞI TARAF İÇİN CONVERSATION KONTROL ET VE OLUŞTUR
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
      AND other_user_id = v_user_id;
    
    -- Alıcı ID'sini belirle
    IF v_user_id = v_sender_id THEN
        v_recipient_id := v_other_user_id;
    ELSE
        v_recipient_id := v_user_id;
    END IF;
    
    -- Gönderen ismini al
    SELECT COALESCE(full_name, username, 'Birisi') INTO v_sender_name
    FROM profiles
    WHERE id = v_sender_id;
    
    -- Karşı taraf için conversation yoksa oluştur
    IF v_other_conv_id IS NULL THEN
        INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count)
        VALUES (v_other_user_id, v_user_id, NEW.content, NEW.created_at, 1);
        
        RAISE NOTICE 'Created conversation for other user: % -> %', v_other_user_id, v_user_id;
    ELSE
        -- Karşı taraf için conversation varsa güncelle
        UPDATE conversations
        SET
            last_message = NEW.content,
            last_message_time = NEW.created_at,
            updated_at = NOW(),
            unread_count = unread_count + 1
        WHERE id = v_other_conv_id;
        
        RAISE NOTICE 'Updated conversation for other user: %', v_other_conv_id;
    END IF;
    
    -- ============================================================================
    -- BÖLÜM 2: PUSH NOTIFICATION GÖNDER
    -- ============================================================================
    
    -- Alıcının FCM token'ını al
    SELECT fcm_token INTO v_recipient_fcm_token
    FROM profiles
    WHERE id = v_recipient_id
    AND fcm_token IS NOT NULL
    AND fcm_token != '';
    
    -- Notification tablosuna kaydet (app içinde görünmesi için)
    INSERT INTO notifications (
        user_id,
        type,
        title,
        content,
        data,
        is_read
    ) VALUES (
        v_recipient_id,
        'message',
        v_sender_name || ' size mesaj gönderdi',
        CASE
            WHEN length(NEW.content) > 100 THEN substring(NEW.content, 1, 100) || '...'
            ELSE NEW.content
        END,
        jsonb_build_object(
            'conversation_id', NEW.conversation_id,
            'sender_id', NEW.sender_id,
            'message_id', NEW.id
        ),
        FALSE
    );
    
    -- Eğer FCM token varsa Edge Function çağır
    IF v_recipient_fcm_token IS NOT NULL AND v_recipient_fcm_token != '' THEN
        -- Edge function çağır (async - hatayı yoksay)
        BEGIN
            PERFORM net.http_post(
                url := current_setting('app.settings.edge_function_url', true) || '/send-push-notification',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
                ),
                body := jsonb_build_object(
                    'fcm_token', v_recipient_fcm_token,
                    'title', v_sender_name || ' size mesaj gönderdi',
                    'body', CASE 
                        WHEN length(NEW.content) > 100 THEN substring(NEW.content, 1, 100) || '...'
                        ELSE NEW.content
                    END,
                    'data', jsonb_build_object(
                        'type', 'new_message',
                        'conversation_id', NEW.conversation_id,
                        'sender_id', NEW.sender_id,
                        'message_id', NEW.id
                    )
                )
            );
            
            RAISE NOTICE 'Push notification sent to user: %', v_recipient_id;
        EXCEPTION WHEN OTHERS THEN
            -- HTTP çağrısı başarısız olsa bile devam et
            RAISE WARNING 'Push notification failed: %', SQLERRM;
        END;
    ELSE
        RAISE LOG 'No FCM token for user %, push notification skipped', v_recipient_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger'ı oluştur
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- Yorumlar
COMMENT ON FUNCTION update_conversation_on_message() IS 
'Yeni mesaj geldiğinde: 1) Hem gönderenin hem alıcının conversation kaydını günceller/oluşturur 2) Push notification gönderir';

-- ============================================================================
-- SONUÇ
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE '✅ CHAT SİSTEMİ TAM DÜZELTME TAMAMLANDI';
    RAISE NOTICE '✅ 1. Karşı taraf için conversation otomatik oluşturulur';
    RAISE NOTICE '✅ 2. Yeni mesajda push notification gönderilir';
    RAISE NOTICE '✅ 3. unread_count doğru hesaplanır';
    RAISE NOTICE '============================================================================';
END $$;
